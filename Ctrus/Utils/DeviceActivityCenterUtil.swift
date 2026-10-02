import DeviceActivity
import FamilyControls
import ManagedSettings
import SwiftUI
import UIKit
import UserNotifications

class DeviceActivityCenterUtil {
  static func scheduleTimerActivity(for profile: BlockedProfiles) {
    // Only schedule if the schedule is active
    guard let schedule = profile.schedule else {
      cancelUpcomingSessionReminders(for: profile)
      return
    }

    let center = DeviceActivityCenter()
    let scheduleTimerActivity = ScheduleTimerActivity()
    let deviceActivityName = scheduleTimerActivity.getDeviceActivityName(
      from: profile.id.uuidString)

    // If the schedule is not active, remove any existing schedule
    if !schedule.isActive {
      stopActivities(for: [deviceActivityName], with: center)
      cancelUpcomingSessionReminders(for: profile)
      return
    }

    let (intervalStart, intervalEnd) = scheduleTimerActivity.getScheduleInterval(from: schedule)
    let deviceActivitySchedule = DeviceActivitySchedule(
      intervalStart: intervalStart,
      intervalEnd: intervalEnd,
      repeats: true,
    )

    do {
      // Remove any existing schedule and create a new one
      stopActivities(for: [deviceActivityName], with: center)
      try center.startMonitoring(deviceActivityName, during: deviceActivitySchedule)
      print("Scheduled restrictions from \(intervalStart) to \(intervalEnd) daily")
    } catch {
      print("Failed to start monitoring: \(error.localizedDescription)")
    }

    scheduleUpcomingSessionReminders(for: profile, schedule: schedule)
  }

  // MARK: - Schedule start reminders

  private static let scheduleReminderMinutesBefore = 5

  static func cancelUpcomingSessionReminders(for profile: BlockedProfiles) {
    let identifiers = Weekday.allCases.map { reminderIdentifier(for: profile, day: $0) }
    UNUserNotificationCenter.current().removePendingNotificationRequests(
      withIdentifiers: identifiers)
  }

  private static func scheduleUpcomingSessionReminders(
    for profile: BlockedProfiles,
    schedule: BlockedProfileSchedule
  ) {
    cancelUpcomingSessionReminders(for: profile)

    let profileId = profile.id
    let profileName = profile.name
    let days = schedule.days
    let center = UNUserNotificationCenter.current()

    // Saving a profile normally dismisses its sheet right away, which can
    // background the app before this authorization round-trip and the
    // `add` calls below finish — silently dropping the reminder with no
    // visible error. A background task keeps the app alive long enough to
    // actually finish registering them.
    var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "ScheduleReminders") {
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }

    func endBackgroundTaskIfNeeded() {
      guard backgroundTask != .invalid else { return }
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }

    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
      guard granted else {
        endBackgroundTaskIfNeeded()
        return
      }

      let group = DispatchGroup()

      for day in days {
        group.enter()

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Starting Soon!")
        content.body = String(localized: "\(profileName) starts in 5 minutes.")
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
          dateMatching: reminderComponents(for: day, schedule: schedule),
          repeats: true
        )

        let request = UNNotificationRequest(
          identifier: reminderIdentifier(forProfileId: profileId, day: day),
          content: content,
          trigger: trigger
        )

        center.add(request) { error in
          if let error {
            print("Failed to schedule start reminder: \(error.localizedDescription)")
          }
          group.leave()
        }
      }

      group.notify(queue: .main) {
        endBackgroundTaskIfNeeded()
      }
    }
  }

  private static func reminderIdentifier(for profile: BlockedProfiles, day: Weekday) -> String {
    reminderIdentifier(forProfileId: profile.id, day: day)
  }

  private static func reminderIdentifier(forProfileId profileId: UUID, day: Weekday) -> String {
    "ScheduleStartReminder:\(profileId.uuidString):\(day.rawValue)"
  }

  private static func reminderComponents(
    for day: Weekday,
    schedule: BlockedProfileSchedule
  ) -> DateComponents {
    let totalStartMinutes = schedule.startHour * 60 + schedule.startMinute
    var reminderMinutes = totalStartMinutes - scheduleReminderMinutesBefore
    var weekdayRawValue = day.rawValue

    // Roll back to the previous day when the reminder falls before midnight
    if reminderMinutes < 0 {
      reminderMinutes += 24 * 60
      weekdayRawValue =
        weekdayRawValue == Weekday.sunday.rawValue
        ? Weekday.saturday.rawValue
        : weekdayRawValue - 1
    }

    var components = DateComponents()
    components.weekday = weekdayRawValue
    components.hour = reminderMinutes / 60
    components.minute = reminderMinutes % 60
    return components
  }

  static func startBreakTimerActivity(for profile: BlockedProfiles) {
    startBreakTimerActivity(
      for: profile,
      durationInSeconds: TimeInterval(profile.breakTimeInMinutes * 60)
    )
  }

  static func startBreakTimerActivity(
    for profile: BlockedProfiles,
    durationInSeconds: TimeInterval
  ) {
    let center = DeviceActivityCenter()
    let breakTimerActivity = BreakTimerActivity()
    let deviceActivityName = breakTimerActivity.getDeviceActivityName(from: profile.id.uuidString)

    let (intervalStart, intervalEnd) = getTimeIntervalStartAndEnd(from: durationInSeconds)
    let deviceActivitySchedule = DeviceActivitySchedule(
      intervalStart: intervalStart,
      intervalEnd: intervalEnd,
      repeats: false,
    )

    do {
      // Remove any existing schedule and create a new one
      stopActivities(for: [deviceActivityName], with: center)
      try center.startMonitoring(deviceActivityName, during: deviceActivitySchedule)
      print("Scheduled break timer activity from \(intervalStart) to \(intervalEnd) daily")
    } catch {
      print("Failed to start break timer activity: \(error.localizedDescription)")
    }
  }

  static func startStrategyTimerActivity(for profile: BlockedProfiles) {
    guard let strategyData = profile.strategyData else {
      print("No strategy data found for profile: \(profile.id.uuidString)")
      return
    }
    let timerData = StrategyTimerData.toStrategyTimerData(from: strategyData)

    let center = DeviceActivityCenter()
    let strategyTimerActivity = StrategyTimerActivity()
    let deviceActivityName = strategyTimerActivity.getDeviceActivityName(
      from: profile.id.uuidString)

    let (intervalStart, intervalEnd) = getTimeIntervalStartAndEnd(
      from: TimeInterval(timerData.durationInMinutes * 60))

    let deviceActivitySchedule = DeviceActivitySchedule(
      intervalStart: intervalStart,
      intervalEnd: intervalEnd,
      repeats: false,
    )

    do {
      // Remove any existing activity and create a new one
      stopActivities(for: [deviceActivityName], with: center)
      try center.startMonitoring(deviceActivityName, during: deviceActivitySchedule)
      print("Scheduled strategy timer activity from \(intervalStart) to \(intervalEnd) daily")
    } catch {
      print("Failed to start strategy timer activity: \(error.localizedDescription)")
    }
  }

  static func removeScheduleTimerActivities(for profile: BlockedProfiles) {
    let scheduleTimerActivity = ScheduleTimerActivity()
    let deviceActivityName = scheduleTimerActivity.getDeviceActivityName(
      from: profile.id.uuidString)
    stopActivities(for: [deviceActivityName])
    cancelUpcomingSessionReminders(for: profile)
  }

  static func removeScheduleTimerActivities(for activity: DeviceActivityName) {
    stopActivities(for: [activity])
  }

  static func removeAllBreakTimerActivities() {
    let center = DeviceActivityCenter()
    let activities = center.activities
    let breakTimerActivity = BreakTimerActivity()
    let breakTimerActivities = breakTimerActivity.getAllBreakTimerActivities(from: activities)
    stopActivities(for: breakTimerActivities, with: center)
  }

  static func removeBreakTimerActivity(for profile: BlockedProfiles) {
    let breakTimerActivity = BreakTimerActivity()
    let deviceActivityName = breakTimerActivity.getDeviceActivityName(from: profile.id.uuidString)
    stopActivities(for: [deviceActivityName])
  }

  static func removeAllStrategyTimerActivities() {
    let center = DeviceActivityCenter()
    let activities = center.activities
    let strategyTimerActivity = StrategyTimerActivity()
    let strategyTimerActivities = strategyTimerActivity.getAllStrategyTimerActivities(
      from: activities)
    stopActivities(for: strategyTimerActivities, with: center)
  }

  static func startPauseTimerActivity(for profile: BlockedProfiles) {
    do {
      try schedulePauseTimerActivity(for: profile)
    } catch {
      print("Failed to start pause timer activity: \(error.localizedDescription)")
    }
  }

  static func schedulePauseTimerActivity(for profile: BlockedProfiles) throws {
    let pauseData = StrategyPauseTimerData.toStrategyPauseTimerData(from: profile.strategyData)

    let center = DeviceActivityCenter()
    let pauseTimerActivity = PauseTimerActivity()
    let deviceActivityName = pauseTimerActivity.getDeviceActivityName(
      from: profile.id.uuidString)

    let (intervalStart, intervalEnd) = getTimeIntervalStartAndEnd(
      from: TimeInterval(pauseData.pauseDurationInMinutes * 60))

    let deviceActivitySchedule = DeviceActivitySchedule(
      intervalStart: intervalStart,
      intervalEnd: intervalEnd,
      repeats: false,
    )

    stopActivities(for: [deviceActivityName], with: center)
    try center.startMonitoring(deviceActivityName, during: deviceActivitySchedule)
    print("Scheduled pause timer activity from \(intervalStart) to \(intervalEnd)")
  }

  static func removePauseTimerActivity(for profile: BlockedProfiles) {
    let pauseTimerActivity = PauseTimerActivity()
    let deviceActivityName = pauseTimerActivity.getDeviceActivityName(
      from: profile.id.uuidString)
    stopActivities(for: [deviceActivityName])
  }

  static func removeAllPauseTimerActivities() {
    let center = DeviceActivityCenter()
    let activities = center.activities
    let pauseTimerActivity = PauseTimerActivity()
    let pauseTimerActivities = pauseTimerActivity.getAllPauseTimerActivities(from: activities)
    stopActivities(for: pauseTimerActivities, with: center)
  }

  static func getActivePauseTimerActivity(for profile: BlockedProfiles) -> DeviceActivityName? {
    let center = DeviceActivityCenter()
    let pauseTimerActivity = PauseTimerActivity()
    let activities = center.activities

    return activities.first(where: {
      $0 == pauseTimerActivity.getDeviceActivityName(from: profile.id.uuidString)
    })
  }

  static func getActiveScheduleTimerActivity(for profile: BlockedProfiles) -> DeviceActivityName? {
    let center = DeviceActivityCenter()
    let scheduleTimerActivity = ScheduleTimerActivity()
    let activities = center.activities

    return activities.first(where: {
      $0 == scheduleTimerActivity.getDeviceActivityName(from: profile.id.uuidString)
    })
  }

  static func getDeviceActivities() -> [DeviceActivityName] {
    let center = DeviceActivityCenter()
    return center.activities
  }

  private static func stopActivities(
    for activities: [DeviceActivityName], with center: DeviceActivityCenter? = nil
  ) {
    let center = center ?? DeviceActivityCenter()

    if activities.isEmpty {
      // No activities to stop
      print("No activities to stop")
      return
    }

    center.stopMonitoring(activities)
  }

  private static func getTimeIntervalStartAndEnd(from durationInSeconds: TimeInterval) -> (
    intervalStart: DateComponents, intervalEnd: DateComponents
  ) {
    let intervalStart = DateComponents(hour: 0, minute: 0, second: 0)

    let now = Date()
    let safeDuration = max(1, durationInSeconds)
    let endDate = min(
      now.addingTimeInterval(safeDuration),
      Calendar.current.startOfDay(for: now).addingTimeInterval((24 * 60 * 60) - 1)
    )
    let intervalEnd = Calendar.current.dateComponents([.hour, .minute, .second], from: endDate)
    return (intervalStart: intervalStart, intervalEnd: intervalEnd)
  }
}
