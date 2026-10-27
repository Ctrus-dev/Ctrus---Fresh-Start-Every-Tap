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

  static func cancelUpcomingSessionReminders(for profile: BlockedProfiles) {
    ScheduleReminderUtil.cancel(forProfileId: profile.id)
  }

  // Puts the reminders back in line with the profile (e.g. after a skip
  // changed) without re-registering the schedule's monitoring itself.
  static func refreshUpcomingSessionReminders(for profile: BlockedProfiles) {
    guard let schedule = profile.schedule, schedule.isActive else {
      cancelUpcomingSessionReminders(for: profile)
      return
    }

    scheduleUpcomingSessionReminders(for: profile, schedule: schedule)
  }

  private static func scheduleUpcomingSessionReminders(
    for profile: BlockedProfiles,
    schedule: BlockedProfileSchedule
  ) {
    cancelUpcomingSessionReminders(for: profile)

    let profileId = profile.id
    let profileName = profile.name
    let skip = profile.scheduleSkip

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

    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
      granted, _ in
      guard granted else {
        endBackgroundTaskIfNeeded()
        return
      }

      ScheduleReminderUtil.sync(
        forProfileId: profileId,
        profileName: profileName,
        schedule: schedule,
        skip: skip
      ) {
        endBackgroundTaskIfNeeded()
      }
    }
  }

  static func isScheduleStartReminder(identifier: String) -> Bool {
    ScheduleReminderUtil.isScheduleStartReminder(identifier: identifier)
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
    // Full dates rather than just a time of day, so a timer that crosses
    // midnight ends when it should instead of being cut short at 23:59:59.
    // The start sits in the past to keep the interval above DeviceActivity's
    // 15 minute minimum, which a short timer started just after midnight
    // would otherwise fall under.
    let calendar = Calendar.current
    let now = Date()
    let endDate = now.addingTimeInterval(max(1, durationInSeconds))
    let startDate = min(calendar.startOfDay(for: now), endDate.addingTimeInterval(-15 * 60))
    let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
    return (
      intervalStart: calendar.dateComponents(components, from: startDate),
      intervalEnd: calendar.dateComponents(components, from: endDate)
    )
  }
}
