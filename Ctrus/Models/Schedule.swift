import Foundation

enum Weekday: Int, CaseIterable, Codable, Equatable {
  case sunday = 1
  case monday
  case tuesday
  case wednesday
  case thursday
  case friday
  case saturday

  var name: String {
    switch self {
    case .sunday: return String(localized: "Sunday")
    case .monday: return String(localized: "Monday")
    case .tuesday: return String(localized: "Tuesday")
    case .wednesday: return String(localized: "Wednesday")
    case .thursday: return String(localized: "Thursday")
    case .friday: return String(localized: "Friday")
    case .saturday: return String(localized: "Saturday")
    }
  }

  var shortLabel: String {
    switch self {
    case .sunday: return String(localized: "Su")
    case .monday: return String(localized: "Mo")
    case .tuesday: return String(localized: "Tu")
    case .wednesday: return String(localized: "We")
    case .thursday: return String(localized: "Th")
    case .friday: return String(localized: "Fr")
    case .saturday: return String(localized: "Sa")
    }
  }
}

struct BlockedProfileSchedule: Codable, Equatable {
  var days: [Weekday]

  var startHour: Int
  var startMinute: Int
  var endHour: Int
  var endMinute: Int

  var updatedAt: Date = Date()

  var isActive: Bool {
    return !days.isEmpty
  }

  var totalDurationInSeconds: Int {
    return (endHour - startHour) * 3600 + (endMinute - startMinute) * 60
  }

  var summaryText: String {
    guard isActive else { return String(localized: "No Schedule Set") }

    let daysSummary =
      days
      .sorted { $0.rawValue < $1.rawValue }
      .map { $0.shortLabel }
      .joined(separator: " ")

    let start = formattedTimeString(hour24: startHour, minute: startMinute)
    let end = formattedTimeString(hour24: endHour, minute: endMinute)

    return "\(daysSummary) · \(start) - \(end)"
  }

  func isTodayScheduled(now: Date = Date(), calendar: Calendar = .current) -> Bool {
    guard isActive else { return false }
    let currentWeekdayRaw = calendar.component(.weekday, from: now)
    guard let today = Weekday(rawValue: currentWeekdayRaw) else { return false }
    return days.contains(today)
  }

  func olderThan15Minutes(now: Date = Date()) -> Bool {
    return now.timeIntervalSince(updatedAt) > 15 * 60
  }

  func nextStartDate(
    now: Date = Date(),
    calendar: Calendar = .current,
    bufferMinutes: Int = 15
  ) -> Date? {
    guard isActive else { return nil }

    let bufferTime = now.addingTimeInterval(TimeInterval(bufferMinutes * 60))

    for daysAhead in 0..<7 {
      guard let candidateDate = calendar.date(byAdding: .day, value: daysAhead, to: bufferTime)
      else {
        continue
      }

      let candidateWeekdayRaw = calendar.component(.weekday, from: candidateDate)
      guard let candidateWeekday = Weekday(rawValue: candidateWeekdayRaw),
        days.contains(candidateWeekday)
      else {
        continue
      }

      guard
        let scheduleStartTime = calendar.date(
          bySettingHour: startHour,
          minute: startMinute,
          second: 0,
          of: candidateDate
        )
      else {
        continue
      }

      if scheduleStartTime >= bufferTime {
        return scheduleStartTime
      }
    }

    return nil
  }

  func nextStartMessage(
    now: Date = Date(),
    calendar: Calendar = .current,
    includePrefix: Bool = true
  ) -> String? {
    guard let nextStart = nextStartDate(now: now, calendar: calendar) else { return nil }

    let timeFormatter = DateFormatter()
    timeFormatter.locale = Locale.autoupdatingCurrent
    timeFormatter.setLocalizedDateFormatFromTemplate("jm")
    let time = timeFormatter.string(from: nextStart)

    let message: String
    if calendar.isDateInToday(nextStart) {
      message = String(localized: "Today at \(time)")
    } else if calendar.isDateInTomorrow(nextStart) {
      message = String(localized: "Tomorrow at \(time)")
    } else {
      let fullFormatter = DateFormatter()
      fullFormatter.locale = Locale.autoupdatingCurrent
      fullFormatter.setLocalizedDateFormatFromTemplate("EEEEMMMdjm")
      message = fullFormatter.string(from: nextStart)
    }

    return includePrefix ? String(localized: "Next start: \(message)") : message
  }

  private func formattedTimeString(hour24: Int, minute: Int) -> String {
    var hour = hour24 % 12
    if hour == 0 { hour = 12 }
    let isPM = hour24 >= 12
    return "\(hour):\(String(format: "%02d", minute)) \(isPM ? "PM" : "AM")"
  }
}
