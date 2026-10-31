import AVFoundation
import ActivityKit
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

  static let silentSoundFile = "alarm_silence.caf"
  /// How long after its alarm an occurrence that never got a session is
  /// still started by the app (StrategyManager), so the alarm can't be
  /// silenced just by opening it. About as long as the spares ring.
  static let missedSessionGrace: TimeInterval = 30 * 60
  // While it rings in the app, the system alarms are held this far ahead,
  // moved every 30 seconds.
  private static let inAppSparesLead: TimeInterval = 60

  /// Sounds offered for the alarm. Each tone is under 30 seconds, the most
  /// AlarmKit plays.
  static let availableSounds =
    BlockedProfileSchedule.alarmToneIds + [BlockedProfileSchedule.vibrateAlarmSound]

  static func soundTitle(for soundId: String) -> String {
    switch soundId {
    case "ctrus_urgent": return String(localized: "Urgent")
    case "ctrus_morning": return String(localized: "Morning")
    case "ctrus_lumen": return String(localized: "Lumen")
    case "ctrus_pulsar": return String(localized: "Pulsar")
    case "ctrus_orbit": return String(localized: "Orbit")
    case "ctrus_lagoon": return String(localized: "Lagoon")
    case "ctrus_spark": return String(localized: "Spark")
    case "ctrus_waves": return String(localized: "Waves")
    case "ctrus_daybreak": return String(localized: "Daybreak")
    case "ctrus_musicbox": return String(localized: "Music Box")
    case "ctrus_rally": return String(localized: "Rally")
    case BlockedProfileSchedule.vibrateAlarmSound: return String(localized: "Vibrate only")
    default: return soundId
    }
  }

  static func isAlarmProfile(_ strategyId: String?) -> Bool {
    strategyId == AlarmBlockingStrategy.id
  }

  static let alarmAccessDeniedMessage = String(
    localized:
      "Without alarm access, Alarm mode can't work. You can turn it on in Settings.")

  static let liveActivitiesOffMessage = String(
    localized:
      "iOS shows the alarm as a Live Activity. Turn Live Activities on for Ctrus in Settings, or the alarm won't come up on the lock screen."
  )

  /// Checked when an Alarm mode profile is saved, asking for alarm access if
  /// it hasn't been yet. Returns why the profile can't be saved, if it can't.
  @MainActor
  static func alarmSetupProblem(for draft: BlockedProfileDraft) async -> String? {
    guard draft.useAlarm else { return nil }
    guard #available(iOS 26.0, *), await AlarmScheduleUtil.requestAuthorization() else {
      return alarmAccessDeniedMessage
    }
    // Unlike alarm access, there's no asking for these: only Settings turns them on.
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      return liveActivitiesOffMessage
    }
    return nil
  }

  @Published private(set) var isRinging = false
  @Published private(set) var snoozedUntil: Date?
  @Published private(set) var dueProfileId: UUID?
  /// Set when the alarm opens the app, so that profile's card opens expanded.
  @Published var expandRequestProfileId: UUID?
  /// Set alongside it, so that card goes straight to scanning the Ctrus.
  @Published var stopRequestProfileId: UUID?
  @Published private(set) var now = Date()

  private struct AlarmRecord: Codable {
    /// When this alarm is due — kept while the spares move about for a
    /// snooze or the app being open.
    var alarmDate: Date
    var alarmIds: [UUID]
    // Optional so records from before these still decode, and get set
    // again with them.
    var allowsSnooze: Bool?
    var soundId: String?
  }

  private let defaults = UserDefaults.standard
  private let recordsKey = "wakeAlarmRecords"
  private let snoozedUntilKey = "wakeAlarmSnoozedUntil"
  private let sessionEndsKey = "wakeAlarmSessionEnds"

  private var player: AVAudioPlayer?
  private var previewPlayer: AVAudioPlayer?
  private var previewStop: DispatchWorkItem?
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

  @discardableResult
  private func enqueue(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
    let previous = lastOperation
    let task = Task { @MainActor in
      await previous?.value
      await operation()
    }
    lastOperation = task
    return task
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
      self.removeStrayAlarms()
      self.updateDueState()
    }
  }

  /// Alarms no record knows about — left by an earlier version, or by a
  /// record that was replaced — would ring, or stay in the Dynamic Island,
  /// with nothing in the app to stop them.
  @available(iOS 26.0, *)
  @MainActor
  private func removeStrayAlarms() {
    let known = Set(records.values.flatMap(\.alarmIds))
    let strays = AlarmScheduleUtil.allAlarms.filter { !known.contains($0.id) }
    AlarmScheduleUtil.cancel(strays.map(\.id))
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

    let allowsSnooze = snapshot.enableSnooze ?? true
    let soundId = snapshot.schedule?.alarmSoundId ?? BlockedProfileSchedule.defaultAlarmSound

    // Already set for this alarm; a due one is looked after by the ringing
    // and snooze below.
    if let record, record.alarmDate == desiredDate, record.allowsSnooze == allowsSnooze,
      record.soundId == soundId
    {
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
      soundId: soundId,
      allowsSnooze: allowsSnooze
    )
    setRecord(
      AlarmRecord(
        alarmDate: desiredDate, alarmIds: ids, allowsSnooze: allowsSnooze, soundId: soundId),
      for: profileId)
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
    stopRequestProfileId = profileId
    updateDueState()
    now = Date()

    // Rang without a session (it didn't start), so there's nothing to stop.
    if dueProfileId != profileId {
      refresh(profileId: profileId)
    }
  }

  func snooze() {
    guard let profileId = dueProfileId else { return }
    Task { await snooze(profileId: profileId) }
  }

  /// Also reached from the alarm's own Snooze button, with the app in the
  /// background, so it waits for the spares to have moved.
  @MainActor
  func snooze(profileId: UUID) async {
    let snoozeMinutes =
      SharedData.snapshot(for: profileId.uuidString)?.schedule?.alarmSnoozeMinutes
      ?? BlockedProfileSchedule.defaultSnoozeMinutes
    let until = Date().addingTimeInterval(TimeInterval(snoozeMinutes * 60))
    setSnoozedUntil(until)
    stopSound()

    if #available(iOS 26.0, *) {
      await enqueue { await self.moveSpares(of: profileId, to: until) }.value
    }
  }

  /// When the running session's alarm is due, kept while a snooze moves the
  /// spares about.
  func alarmDate(for profileId: UUID) -> Date? {
    records[profileId.uuidString]?.alarmDate
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
    // Only meant for the opening the alarm caused.
    stopRequestProfileId = nil

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
      let sparesAt = currentDate.addingTimeInterval(Self.inAppSparesLead)
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

    let allowsSnooze = snapshot.enableSnooze ?? true
    let soundId = snapshot.schedule?.alarmSoundId ?? BlockedProfileSchedule.defaultAlarmSound
    AlarmScheduleUtil.cancel(record.alarmIds)
    record.alarmIds = await AlarmScheduleUtil.schedule(
      at: date,
      profileId: profileId,
      profileName: snapshot.name,
      soundId: soundId,
      allowsSnooze: allowsSnooze
    )
    record.allowsSnooze = allowsSnooze
    record.soundId = soundId
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

    // The system alarm vibrates alongside its sound, so the app does too.
    vibrationTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
      AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

    guard soundId != BlockedProfileSchedule.vibrateAlarmSound else { return }

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
    previewPlayer?.stop()
    previewPlayer = makePlayer(for: soundId)
    previewPlayer?.numberOfLoops = -1
    previewPlayer?.prepareToPlay()
    previewPlayer?.play()

    // Replaced on every pick, so an earlier pick's stop can't cut this one
    // short — or stop it before it's heard at all.
    previewStop?.cancel()
    let stop = DispatchWorkItem { [weak self] in
      self?.previewPlayer?.stop()
      self?.previewPlayer = nil
    }
    previewStop = stop
    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: stop)
  }

  private func makePlayer(for soundId: String) -> AVAudioPlayer? {
    guard let url = Bundle.main.url(forResource: soundId, withExtension: "caf") else {
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
