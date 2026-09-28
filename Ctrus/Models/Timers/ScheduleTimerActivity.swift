import DeviceActivity
import OSLog
import UserNotifications

private let log: Logger = Logger(subsystem: "com.Ctrus.monitor", category: ScheduleTimerActivity.id)

class ScheduleTimerActivity: TimerActivity {
  static var id: String = "ScheduleTimerActivity"

  private let appBlocker = AppBlockerUtil()

  func getDeviceActivityName(from profileId: String) -> DeviceActivityName {
    // Since schedules were implemented before the timer activities, the profile id is used as the device activity name for
    // backward compatibility
    return DeviceActivityName(rawValue: profileId)
  }

  func getAllScheduleTimerActivities(from activities: [DeviceActivityName]) -> [DeviceActivityName]
  {
    // Schedule timer activities use just the profile UUID as the rawValue (no prefix)
    // Other activities use prefixes like "BreakScheduleActivity:" or "StrategyTimerActivity:"
    return activities.filter { activity in
      let rawValue = activity.rawValue
      // If it contains ":", it's a prefixed activity (break or strategy timer), not a schedule
      guard !rawValue.contains(":") else { return false }
      // Must be a valid UUID
      return UUID(uuidString: rawValue) != nil
    }
  }

  func start(for profile: SharedData.ProfileSnapshot) {
    let profileId = profile.id.uuidString

    guard let schedule = profile.schedule
    else {
      log.info("Start schedule timer activity for \(profileId), no schedule for profile found")
      return
    }

    if !schedule.isTodayScheduled() {
      log.info(
        "Start schedule timer activity for \(profileId), schedule is not scheduled for today")
      return
    }

    if !schedule.olderThan15Minutes() {
      log.info("Start schedule timer activity for \(profileId), schedule is too new")
      return
    }

    log.info("Start schedule timer activity for \(profileId), profile: \(profileId)")

    if let existingSession = SharedData.getActiveSharedSession() {
      if existingSession.blockedProfileId == profile.id {
        log.info(
          "Start schedule timer activity for \(profileId), existing session profile matches device activity profile, continuing active session"
        )
        return
      }

      // A different profile is already active (started manually, by NFC, or
      // by another schedule). Never end it or swap its restrictions here —
      // leave it running until it's stopped the normal way, and just skip
      // this trigger.
      log.info(
        "Start schedule timer activity for \(profileId), a different profile is already active, skipping"
      )
      notifyBlockedBySkippedStart(for: profile, activeProfileId: existingSession.blockedProfileId)
      return
    }

    // Create a new active scheduled session for the profile
    SharedData.createSessionForSchedular(for: profile.id)

    // Start restrictions
    appBlocker.activateRestrictions(for: profile)
  }

  private func notifyBlockedBySkippedStart(
    for profile: SharedData.ProfileSnapshot,
    activeProfileId: UUID
  ) {
    let activeProfileName = SharedData.snapshot(for: activeProfileId.uuidString)?.name

    let content = UNMutableNotificationContent()
    content.title = String(localized: "Couldn't Start")
    content.body =
      if let activeProfileName {
        String(
          localized: "\(profile.name) didn't start because \(activeProfileName) is still active.")
      } else {
        String(localized: "\(profile.name) didn't start because another profile is still active.")
      }
    content.sound = .default

    let request = UNNotificationRequest(
      identifier: "ScheduleSkippedStart:\(profile.id.uuidString):\(Date().timeIntervalSince1970)",
      content: content,
      trigger: nil
    )

    UNUserNotificationCenter.current().add(request) { error in
      if let error {
        log.error("Failed to schedule skipped-start notification: \(error.localizedDescription)")
      }
    }
  }

  func stop(for profile: SharedData.ProfileSnapshot) {
    // Scheduled sessions only ever start automatically. Ending one always
    // requires scanning the Ctrus NFC tag in the app, same as any other
    // physically-unlocked profile, so the interval ending here does not
    // touch restrictions or the active session.
    log.info(
      "Interval ended for scheduled profile \(profile.id.uuidString), leaving restrictions active until the Ctrus is scanned"
    )
  }

  func getScheduleInterval(from schedule: BlockedProfileSchedule) -> (
    intervalStart: DateComponents, intervalEnd: DateComponents
  ) {
    let intervalStart = DateComponents(hour: schedule.startHour, minute: schedule.startMinute)
    let intervalEnd = DateComponents(hour: schedule.endHour, minute: schedule.endMinute)
    return (intervalStart: intervalStart, intervalEnd: intervalEnd)
  }
}
