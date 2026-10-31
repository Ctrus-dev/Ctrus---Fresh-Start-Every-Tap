import AVFoundation
import AudioToolbox
import Foundation
import SwiftUI
import UIKit

/// Alarm mode's alarm, from the night before to the Ctrus tap.
///
/// The system alarm for a profile's next session is set ahead of time, from
/// the app: sessions start inside the Screen Time extension, with the app
/// closed, where AlarmKit can't be relied on. Once the alarm is due, the
/// sound carries on inside the app until the session ends; whenever the app
/// is left, the system alarm takes over straight away.
final class WakeAlarmManager: ObservableObject {
  static let shared = WakeAlarmManager()

  static let snoozeSeconds: TimeInterval = 60
  static let silentSoundFile = "alarm_silence.caf"
  // Stands in for the system alarm sound inside the app, which apps can't play.
  private static let inAppDefaultSoundFile = "alarm_beep"
  /// How long after its alarm an occurrence that never got a session is
  /// still started by the app (StrategyManager), so the alarm can't be
  /// silenced just by opening it. About as long as the spares ring.
  static let missedSessionGrace: TimeInterval = 30 * 60

  /// Sounds offered for the alarm. Files dropped into `alarm_sounds/` are
  /// added here by their name, without the extension.
  static let availableSounds = [
    BlockedProfileSchedule.vibrateAlarmSound,
    BlockedProfileSchedule.defaultAlarmSound,
  ]

  static func soundTitle(for soundId: String) -> String {
    switch soundId {
    case BlockedProfileSchedule.vibrateAlarmSound: return String(localized: "Vibrate only")
    case BlockedProfileSchedule.defaultAlarmSound: return String(localized: "Ctrus Alarm")
    default: return soundId
    }
  }

  static func isAlarmProfile(_ strategyId: String?) -> Bool {
    strategyId == AlarmBlockingStrategy.id
  }

  static let alarmAccessDeniedMessage = String(
    localized:
      "Without alarm access, Alarm mode can't work. You can turn it on in Settings.")

  /// Asked when an Alarm mode profile is saved; without it the profile isn't.
  @MainActor
  static func requestAlarmAccessIfNeeded(for draft: BlockedProfileDraft) async -> Bool {
    guard draft.useAlarm else { return true }
    guard #available(iOS 26.0, *) else { return false }
    return await AlarmScheduleUtil.requestAuthorization()
  }

  @Published private(set) var isRinging = false
  @Published private(set) var snoozedUntil: Date?
  @Published private(set) var dueProfileId: UUID?
  /// Set when the alarm opens the app, so that profile's card opens expanded.
  @Published var expandRequestProfileId: UUID?
  @Published private(set) var now = Date()

  private struct AlarmRecord: Codable {
    /// When this alarm is due — kept while the spares move about for a
    /// snooze or the app being open.
    var alarmDate: Date
    var alarmIds: [UUID]
  }

  private let defaults = UserDefaults.standard
  private let recordsKey = "wakeAlarmRecords"
  private let snoozedUntilKey = "wakeAlarmSnoozedUntil"
  private let sessionEndsKey = "wakeAlarmSessionEnds"

  private var player: AVAudioPlayer?
  private var previewPlayer: AVAudioPlayer?
  private var vibrationTimer: Timer?
  private var tickTimer: Timer?
  private var lastSparesPush = Date.distantPast
  // AlarmKit calls run one after another, so two refreshes can't both set an
  // alarm for the same profile and leave one of them behind.
  private var lastOperation: Task<Void, Never>?

  private init() {
    snoozedUntil = defaults.object(forKey: snoozedUntilKey) as? Date

    let center = NotificationCenter.default
    center.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.appBecameActive()
    }
    center.addObserver(
      forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.appEnteredBackground()
    }

    // Opened by the alarm, the app can already be active by the time this exists.
    if UIApplication.shared.applicationState == .active {
      appBecameActive()
    }
  }

  private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
    let previous = lastOperation
    lastOperation = Task { @MainActor in
      await previous?.value
      await operation()
    }
  }

  // MARK: - Keeping the alarms in line with the profiles

  /// Sets, moves or cancels this profile's alarm to match its schedule and
  /// session. Safe to call any time.
  func refresh(profileId: UUID) {
    guard #available(iOS 26.0, *) else { return }
    enqueue { await self.refreshAlarm(for: profileId) }
  }

  func refreshAll() {
    guard #available(iOS 26.0, *) else { return }
    enqueue {
      var profileIds = Set(SharedData.profileSnapshots.keys.compactMap(UUID.init(uuidString:)))
      profileIds.formUnion(self.records.keys.compactMap(UUID.init(uuidString:)))
      for profileId in profileIds {
        await self.refreshAlarm(for: profileId)
      }
      self.updateDueState()
    }
  }

  @available(iOS 26.0, *)
  @MainActor
  private func refreshAlarm(for profileId: UUID) async {
    let record = records[profileId.uuidString]
    let desiredDate = desiredAlarmDate(for: profileId)

    guard let desiredDate, let snapshot = SharedData.snapshot(for: profileId.uuidString) else {
      if let record {
        AlarmScheduleUtil.cancel(record.alarmIds)
        setRecord(nil, for: profileId)
      }
      return
    }

    // Already set for this alarm; a due one is looked after by the ringing
    // and snooze below.
    if let record, record.alarmDate == desiredDate {
      return
    }

    if let record {
      AlarmScheduleUtil.cancel(record.alarmIds)
    }

    // A running session's alarm can already be due.
    let ids = await AlarmScheduleUtil.schedule(
      at: max(desiredDate, Date().addingTimeInterval(1)),
      profileId: profileId,
      profileName: snapshot.name,
      soundId: snapshot.schedule?.alarmSoundId ?? BlockedProfileSchedule.defaultAlarmSound
    )
    setRecord(AlarmRecord(alarmDate: desiredDate, alarmIds: ids), for: profileId)
  }

  /// The running session's alarm, or else the next session's.
  private func desiredAlarmDate(for profileId: UUID, now: Date = Date()) -> Date? {
    guard let snapshot = SharedData.snapshot(for: profileId.uuidString),
      Self.isAlarmProfile(snapshot.blockingStrategyId),
      let schedule = snapshot.schedule, schedule.isActive
    else {
      return nil
    }

    if let session = SharedData.getActiveSharedSession(), session.blockedProfileId == profileId {
      return schedule.alarmDate(after: session.startTime)
    }

    // An occurrence under way without a session gets one from the app, so
    // its alarm stays — unless its session already ran and was stopped.
    if let start = schedule.currentAlarmOccurrenceStart(
      now: now, grace: Self.missedSessionGrace, skip: snapshot.scheduleSkip),
      start > sessionEnds[profileId.uuidString] ?? .distantPast
    {
      return schedule.alarmDate(after: start)
    }

    // Otherwise the next occurrence's, leaving out one too close to the last
    // save for the Screen Time extension to start.
    var searchFrom = now
    while let start = schedule.nextStartDate(
      now: searchFrom, bufferSeconds: 0, skip: snapshot.scheduleSkip)
    {
      if schedule.isPastRegistrationSettleWindow(now: start) {
        return schedule.alarmDate(after: start)
      }
      searchFrom = start.addingTimeInterval(1)
    }
    return nil
  }

  // MARK: - The session's end

  /// The Ctrus or an emergency unblock ended the session: silence it and set
  /// the next session's alarm.
  func sessionEnded(profileId: UUID) {
    stopSound()
    setSnoozedUntil(nil)
    setDueProfileId(nil)
    setSessionEnd(Date(), for: profileId)

    guard #available(iOS 26.0, *) else { return }
    enqueue {
      if let record = self.records[profileId.uuidString] {
        AlarmScheduleUtil.cancel(record.alarmIds)
        self.setRecord(nil, for: profileId)
      }
      await self.refreshAlarm(for: profileId)
    }
  }

  // MARK: - Ringing

  /// Slid away on the alarm: the app opens on this profile.
  func alarmOpenedApp(profileId: String) {
    guard let profileId = UUID(uuidString: profileId) else { return }
    expandRequestProfileId = profileId
    updateDueState()
    now = Date()

    // Rang without a session (it didn't start), so there's nothing to stop.
    if dueProfileId != profileId {
      refresh(profileId: profileId)
    }
  }

  func snooze() {
    guard let profileId = dueProfileId else { return }
    let until = Date().addingTimeInterval(Self.snoozeSeconds)
    setSnoozedUntil(until)
    stopSound()

    if #available(iOS 26.0, *) {
      enqueue { await self.moveSpares(of: profileId, to: until) }
    }
  }

  var isSnoozed: Bool {
    guard let snoozedUntil else { return false }
    return snoozedUntil > now
  }

  private func appBecameActive() {
    refreshAll()
    startTicking()
  }

  private func appEnteredBackground() {
    tickTimer?.invalidate()
    tickTimer = nil

    guard isRinging, let profileId = dueProfileId else { return }
    stopSound()

    // The sound can't outlive the app, so the system alarm comes straight
    // back. Leaving to force-quit the app comes through here too.
    guard #available(iOS 26.0, *) else { return }
    let backgroundTask = UIApplication.shared.beginBackgroundTask()
    let ringAgainAt = Date().addingTimeInterval(1)
    enqueue {
      await self.moveSpares(of: profileId, to: ringAgainAt)
      UIApplication.shared.endBackgroundTask(backgroundTask)
    }
  }

  private func startTicking() {
    tickTimer?.invalidate()
    tick()
    tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      self?.tick()
    }
  }

  private func tick() {
    let currentDate = Date()
    // Only the snooze countdown shows the time, so the cards aren't redrawn
    // every second for nothing.
    if snoozedUntil != nil {
      now = currentDate
    }
    updateDueState()

    guard let profileId = dueProfileId else {
      stopSound()
      return
    }

    // Ends a second early so the app takes over before the system alarm set
    // for the end of the snooze goes off.
    if let snoozedUntil, snoozedUntil.timeIntervalSince(currentDate) > 1 {
      return
    }
    if snoozedUntil != nil {
      setSnoozedUntil(nil)
    }

    if !isRinging {
      startSound(for: profileId)
    }

    // While it rings in the app the system alarms are kept a minute ahead,
    // so they only ring once the app is gone.
    if #available(iOS 26.0, *), currentDate.timeIntervalSince(lastSparesPush) >= 30 {
      lastSparesPush = currentDate
      let sparesAt = currentDate.addingTimeInterval(AlarmScheduleUtil.alarmRepeatSeconds)
      enqueue { await self.moveSpares(of: profileId, to: sparesAt) }
    }
  }

  private func updateDueState() {
    guard let session = SharedData.getActiveSharedSession(),
      let record = records[session.blockedProfileId.uuidString],
      record.alarmDate <= Date()
    else {
      setDueProfileId(nil)
      return
    }
    setDueProfileId(session.blockedProfileId)
  }

  private func setDueProfileId(_ profileId: UUID?) {
    guard dueProfileId != profileId else { return }
    dueProfileId = profileId
  }

  @available(iOS 26.0, *)
  @MainActor
  private func moveSpares(of profileId: UUID, to date: Date) async {
    guard var record = records[profileId.uuidString],
      let snapshot = SharedData.snapshot(for: profileId.uuidString)
    else {
      return
    }

    AlarmScheduleUtil.cancel(record.alarmIds)
    record.alarmIds = await AlarmScheduleUtil.schedule(
      at: date,
      profileId: profileId,
      profileName: snapshot.name,
      soundId: snapshot.schedule?.alarmSoundId ?? BlockedProfileSchedule.defaultAlarmSound
    )
    setRecord(record, for: profileId)
  }

  // MARK: - Sound

  private func startSound(for profileId: UUID) {
    let soundId =
      SharedData.snapshot(for: profileId.uuidString)?.schedule?.alarmSoundId
      ?? BlockedProfileSchedule.defaultAlarmSound

    do {
      try AVAudioSession.sharedInstance().setCategory(.playback)
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("Alarm mode: couldn't start the audio session: \(error)")
    }

    isRinging = true
    lastSparesPush = .distantPast

    if soundId == BlockedProfileSchedule.vibrateAlarmSound {
      vibrationTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
      }
      AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
      return
    }

    player = makePlayer(for: soundId)
    player?.numberOfLoops = -1
    player?.play()
  }

  private func stopSound() {
    player?.stop()
    player = nil
    vibrationTimer?.invalidate()
    vibrationTimer = nil

    guard isRinging else { return }
    isRinging = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  /// Plays a sound for 3 seconds while choosing it.
  func previewSound(_ soundId: String) {
    guard !isRinging else { return }

    if soundId == BlockedProfileSchedule.vibrateAlarmSound {
      AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
      return
    }

    try? AVAudioSession.sharedInstance().setCategory(.playback)
    try? AVAudioSession.sharedInstance().setActive(true)
    previewPlayer = makePlayer(for: soundId)
    previewPlayer?.numberOfLoops = -1
    previewPlayer?.play()

    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
      self?.previewPlayer?.stop()
      self?.previewPlayer = nil
    }
  }

  private func makePlayer(for soundId: String) -> AVAudioPlayer? {
    let fileName =
      soundId == BlockedProfileSchedule.defaultAlarmSound ? Self.inAppDefaultSoundFile : soundId
    guard let url = Bundle.main.url(forResource: fileName, withExtension: "caf") else {
      return nil
    }
    return try? AVAudioPlayer(contentsOf: url)
  }

  // MARK: - Storage

  private var records: [String: AlarmRecord] {
    guard let data = defaults.data(forKey: recordsKey) else { return [:] }
    return (try? JSONDecoder().decode([String: AlarmRecord].self, from: data)) ?? [:]
  }

  private func setRecord(_ record: AlarmRecord?, for profileId: UUID) {
    var all = records
    all[profileId.uuidString] = record
    if let data = try? JSONEncoder().encode(all) {
      defaults.set(data, forKey: recordsKey)
    }
  }

  private var sessionEnds: [String: Date] {
    defaults.dictionary(forKey: sessionEndsKey) as? [String: Date] ?? [:]
  }

  private func setSessionEnd(_ date: Date, for profileId: UUID) {
    var all = sessionEnds
    all[profileId.uuidString] = date
    defaults.set(all, forKey: sessionEndsKey)
  }

  private func setSnoozedUntil(_ date: Date?) {
    now = Date()
    snoozedUntil = date
    defaults.set(date, forKey: snoozedUntilKey)
  }
}
