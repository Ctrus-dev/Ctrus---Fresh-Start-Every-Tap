import DeviceActivity
import Foundation
import OSLog
import UserNotifications

private let log = Logger(subsystem: "com.Ctrus.monitor", category: "ChildSessionLimit")

// Child mode's automatic end: every session stops after 24 hours at most, or
// sooner for a schedule's fixed duration. The system wakes us
// through DeviceActivity, which follows the phone's date — so before ending
// anything, the real time since the session started is checked with
// TrustedClock, and if it hasn't actually passed the end is set again for
// what's left. Shared with the device monitor so it works with the app closed.
//
// Outside child mode the same check guards a Schedule mode session with a
// fixed duration and a timer session, so moving the date forward can't end
// them early.
enum ChildSessionLimit {
  static let activityId = "ChildSessionLimitActivity"
  static let maxSessionDuration: TimeInterval = 24 * 60 * 60
  static let reminderLeadTime: TimeInterval = 5 * 60

  private static let suite = UserDefaults(suiteName: "group.mo.dev.Ctrus")!
  private static let clock = TrustedClock(key: "childSession", defaults: suite)

  private enum Key: String {
    case childSessionId
    case childSessionElapsed
    case childSessionStartedAt
  }

  struct Plan: Equatable {
    /// Real time the session may run for, counted from its start.
    let limit: TimeInterval
    /// It ends to make way for the same schedule's next session, so the
    /// "starts in 5 minutes" reminder is shown as it ends.
    let makesWayForNextSession: Bool
  }

  static func activityName(for profileId: UUID) -> DeviceActivityName {
    DeviceActivityName(rawValue: "\(activityId):\(profileId.uuidString)")
  }

  // MARK: - Session lifecycle

  static func begin(sessionId: String, profile: SharedData.ProfileSnapshot, startedAt: Date) {
    guard ChildModeStore.isChildMode || hasFixedEnd(profile) else { return }

    // Reading the clock here resets it, so only time from now on is counted.
    _ = clock.trustedElapsed()
    suite.set(sessionId, forKey: Key.childSessionId.rawValue)
    suite.set(0.0, forKey: Key.childSessionElapsed.rawValue)
    suite.set(startedAt.timeIntervalSinceReferenceDate, forKey: Key.childSessionStartedAt.rawValue)

    let plan = plan(for: profile, startedAt: startedAt)
    scheduleCheck(for: profile.id, in: plan.limit)
  }

  /// The session ended some other way; drop its automatic end.
  static func end() {
    if let profileId = SharedData.getActiveSharedSession()?.blockedProfileId {
      DeviceActivityCenter().stopMonitoring([activityName(for: profileId)])
    } else {
      let center = DeviceActivityCenter()
      let names = center.activities.filter { $0.rawValue.hasPrefix("\(activityId):") }
      if !names.isEmpty { center.stopMonitoring(names) }
    }
    clear()
  }

  /// Whether this limit decides when the active session ends.
  static var tracksActiveSession: Bool {
    guard let sessionId = suite.string(forKey: Key.childSessionId.rawValue) else { return false }
    return SharedData.getActiveSharedSession()?.id == sessionId
  }

  /// Ends the session if its real time is up, otherwise sets the next check.
  /// Returns whether it ended the session.
  @discardableResult
  static func check() -> Bool {
    guard let sessionId = suite.string(forKey: Key.childSessionId.rawValue),
      let activeSession = SharedData.getActiveSharedSession(),
      activeSession.id == sessionId,
      let profile = SharedData.snapshot(for: activeSession.blockedProfileId.uuidString)
    else {
      return false
    }

    if ChildModeStore.isChildMode {
      ChildModeStore.checkForClockChange()
    }

    let elapsed = suite.double(forKey: Key.childSessionElapsed.rawValue) + clock.trustedElapsed()
    suite.set(elapsed, forKey: Key.childSessionElapsed.rawValue)

    let startedAt = Date(
      timeIntervalSinceReferenceDate: suite.double(forKey: Key.childSessionStartedAt.rawValue))
    let plan = plan(for: profile, startedAt: startedAt)

    // A few seconds' slack, as the system can wake us marginally early.
    let remaining = plan.limit - elapsed
    guard remaining <= 5 else {
      log.info("Session \(sessionId) has \(remaining)s of real time left, checking again then")
      scheduleCheck(for: profile.id, in: remaining)
      return false
    }

    log.info("Session \(sessionId) reached its real time limit, ending it")
    DeviceActivityCenter().stopMonitoring([activityName(for: profile.id)])
    AppBlockerUtil().deactivateRestrictions()
    SharedData.endActiveSharedSession()
    clear()

    if plan.makesWayForNextSession {
      notifyNextSessionStartsSoon(profileName: profile.name)
    }

    ScheduleReminderUtil.sync(
      forProfileId: profile.id,
      profileName: profile.name,
      schedule: profile.schedule,
      skip: profile.scheduleSkip
    )
    return true
  }

  // MARK: - Planning

  static func plan(
    for profile: SharedData.ProfileSnapshot,
    startedAt: Date,
    calendar: Calendar = .current
  ) -> Plan {
    guard ChildModeStore.isChildMode else {
      let limit =
        timerDuration(of: profile)
        ?? remainingFixedDuration(for: profile, startedAt: startedAt, calendar: calendar)
      return Plan(limit: limit, makesWayForNextSession: false)
    }

    var limit = maxSessionDuration

    guard let schedule = profile.schedule, schedule.isActive else {
      return Plan(limit: limit, makesWayForNextSession: false)
    }

    if let duration = schedule.automaticEndDurationInSeconds {
      limit = min(limit, duration)
    }

    // Still running when the same schedule's next session comes round: it
    // ends at that session's 5-minute reminder, and the new one starts on
    // time. Unless that next one is skipped — then nothing ends here.
    let skip = profile.allowSkip == true ? profile.scheduleSkip : ScheduleSkip()
    if let nextStart = schedule.nextStartDate(
      now: startedAt, calendar: calendar, bufferSeconds: reminderLeadTime + 60),
      !skip.skips(occurrenceStartingAt: nextStart, calendar: calendar)
    {
      let makeWayAt = nextStart.addingTimeInterval(-reminderLeadTime).timeIntervalSince(startedAt)
      if makeWayAt < limit {
        return Plan(limit: max(0, makeWayAt), makesWayForNextSession: true)
      }
    }

    return Plan(limit: limit, makesWayForNextSession: false)
  }

  // Spelled out: the strategy types aren't part of the device monitor.
  private static let timerStrategyIds: Set<String> = [
    "NFCTimerBlockingStrategy", "ShortcutTimerBlockingStrategy",
  ]

  static func hasFixedEnd(_ profile: SharedData.ProfileSnapshot) -> Bool {
    if timerDuration(of: profile) != nil { return true }
    guard profile.blockingStrategyId == "ScheduleBlockingStrategy",
      let schedule = profile.schedule
    else { return false }
    return schedule.isActive && schedule.hasAutomaticEnd
  }

  private static func timerDuration(of profile: SharedData.ProfileSnapshot) -> TimeInterval? {
    guard timerStrategyIds.contains(profile.blockingStrategyId ?? ""),
      let strategyData = profile.strategyData
    else { return nil }
    // StrategyTimerData's duration, which falls back to 15 minutes the same way.
    let minutes = (try? JSONDecoder().decode(TimerDuration.self, from: strategyData))?
      .durationInMinutes ?? 15
    return TimeInterval(minutes * 60)
  }

  private struct TimerDuration: Decodable {
    let durationInMinutes: Int
  }

  /// The fixed duration counts from the schedule's start, so a session that
  /// began a little late still ends when its window does.
  static func remainingFixedDuration(
    for profile: SharedData.ProfileSnapshot,
    startedAt: Date,
    calendar: Calendar = .current
  ) -> TimeInterval {
    guard let schedule = profile.schedule,
      let duration = schedule.automaticEndDurationInSeconds,
      var windowStart = calendar.date(
        bySettingHour: schedule.startHour, minute: schedule.startMinute, second: 0, of: startedAt)
    else {
      return maxSessionDuration
    }
    if windowStart > startedAt,
      let previousDay = calendar.date(byAdding: .day, value: -1, to: windowStart)
    {
      windowStart = previousDay
    }
    return max(0, duration - startedAt.timeIntervalSince(windowStart))
  }

  // MARK: - Helpers

  private static func scheduleCheck(for profileId: UUID, in seconds: TimeInterval) {
    let center = DeviceActivityCenter()
    let name = activityName(for: profileId)

    // Full dates so it can run past midnight; the start sits in the past to
    // stay above DeviceActivity's 15-minute minimum interval.
    let calendar = Calendar.current
    let now = Date()
    let endDate = now.addingTimeInterval(max(1, seconds))
    let startDate = min(calendar.startOfDay(for: now), endDate.addingTimeInterval(-15 * 60))
    let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]

    let schedule = DeviceActivitySchedule(
      intervalStart: calendar.dateComponents(components, from: startDate),
      intervalEnd: calendar.dateComponents(components, from: endDate),
      repeats: false
    )

    center.stopMonitoring([name])
    do {
      try center.startMonitoring(name, during: schedule)
    } catch {
      log.error("Failed to schedule the real time limit: \(error.localizedDescription)")
    }
  }

  private static func notifyNextSessionStartsSoon(profileName: String) {
    let content = UNMutableNotificationContent()
    content.title = String(localized: "Starting Soon!")
    content.body = String(localized: "\(profileName) starts in 5 minutes.")
    content.sound = .default

    let request = UNNotificationRequest(
      identifier: "ChildModeNextSession:\(Date().timeIntervalSince1970)",
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request)
  }

  private static func clear() {
    suite.removeObject(forKey: Key.childSessionId.rawValue)
    suite.removeObject(forKey: Key.childSessionElapsed.rawValue)
    suite.removeObject(forKey: Key.childSessionStartedAt.rawValue)
  }
}
