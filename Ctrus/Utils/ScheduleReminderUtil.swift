import Foundation
import UserNotifications

// Shared with the device monitor extension, which starts and ends schedule
// sessions while the app isn't running and has to keep these in step.
enum ScheduleReminderUtil {
  private static let reminderMinutesBefore = 5
  private static let identifierPrefix = "ScheduleStartReminder:"

  static func isScheduleStartReminder(identifier: String) -> Bool {
    identifier.hasPrefix(identifierPrefix)
  }

  static func cancel(forProfileId profileId: UUID) {
    let identifiers = Weekday.allCases.map { identifier(forProfileId: profileId, day: $0) }
    UNUserNotificationCenter.current().removePendingNotificationRequests(
      withIdentifiers: identifiers)
  }

  // The reminders repeat on the calendar with nothing checking the session
  // when they fire, so while this profile is already blocking (an indefinite
  // schedule can run past its next start) they're taken down entirely and
  // only put back once the session ends. A day whose next occurrence is
  // skipped is left out the same way, until that occurrence has gone by.
  static func sync(
    forProfileId profileId: UUID,
    profileName: String,
    schedule: BlockedProfileSchedule?,
    skip: ScheduleSkip = ScheduleSkip(),
    completion: (() -> Void)? = nil
  ) {
    cancel(forProfileId: profileId)

    guard let schedule, schedule.isActive,
      SharedData.getActiveSharedSession()?.blockedProfileId != profileId
    else {
      completion?()
      return
    }

    let center = UNUserNotificationCenter.current()
    let group = DispatchGroup()

    let now = Date()
    let daysToRemind = schedule.days.filter { day in
      guard
        let occurrenceStart = schedule.nextOccurrenceStart(
          on: day, remindingMinutesBefore: reminderMinutesBefore, after: now)
      else {
        return true
      }
      return !skip.skips(occurrenceStartingAt: occurrenceStart)
    }

    for day in daysToRemind {
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
        identifier: identifier(forProfileId: profileId, day: day),
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
      completion?()
    }
  }

  private static func identifier(forProfileId profileId: UUID, day: Weekday) -> String {
    "\(identifierPrefix)\(profileId.uuidString):\(day.rawValue)"
  }

  private static func reminderComponents(
    for day: Weekday,
    schedule: BlockedProfileSchedule
  ) -> DateComponents {
    let totalStartMinutes = schedule.startHour * 60 + schedule.startMinute
    var reminderMinutes = totalStartMinutes - reminderMinutesBefore
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
}
