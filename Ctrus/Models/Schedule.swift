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
  /// Hour counts a session can run for before it stops on its own.
  static let availableDurationsInHours = [1, 2, 3, 4]

  var days: [Weekday]

  var startHour: Int
  var startMinute: Int

  // Superseded by `durationInHours`, which is what the monitored interval is
  // built from now. Kept only so already-stored schedules keep decoding.
  var endHour: Int = 23
  var endMinute: Int = 59

  /// `nil` runs until the Ctrus is scanned; otherwise the session stops on its
  /// own after this many hours.
  var durationInHours: Int?

  var updatedAt: Date = Date()

  var isActive: Bool {
    return !days.isEmpty
  }

  var hasAutomaticEnd: Bool {
    return durationInHours != nil
  }

  var automaticEndDurationInSeconds: TimeInterval? {
    guard let durationInHours else { return nil }
    return TimeInterval(durationInHours * 3600)
  }

  /// Wall clock end of the window DeviceActivity monitors. An indefinite
  /// schedule still needs one, so it holds the window open until the end of the
  /// day — nothing stops when it closes.
  var endComponents: (hour: Int, minute: Int) {
    guard let durationInHours else { return (23, 59) }

    let minutesFromMidnight =
      (startHour * 60 + startMinute + durationInHours * 60) % (24 * 60)
    return (minutesFromMidnight / 60, minutesFromMidnight % 60)
  }

  static func durationText(forHours hours: Int?) -> String {
    guard let hours else { return String(localized: "Indefinite") }
    return hours == 1 ? String(localized: "1 hour") : String(localized: "\(hours) hours")
  }

  var durationText: String {
    return Self.durationText(forHours: durationInHours)
  }

  var summaryText: String {
    guard isActive else { return String(localized: "No Schedule Set") }

    let daysSummary =
      days
      .sorted { $0.rawValue < $1.rawValue }
      .map { $0.shortLabel }
      .joined(separator: " ")

    let start = formattedTimeString(hour24: startHour, minute: startMinute)

    return "\(daysSummary) · \(start) · \(durationText)"
  }

  func isTodayScheduled(now: Date = Date(), calendar: Calendar = .current) -> Bool {
    guard isActive else { return false }
    let currentWeekdayRaw = calendar.component(.weekday, from: now)
    guard let today = Weekday(rawValue: currentWeekdayRaw) else { return false }
    return days.contains(today)
  }

  // DeviceActivityCenter can fire `intervalDidStart` the instant monitoring
  // is (re-)registered if "now" already falls inside today's configured
  // window — which happens on every schedule edit, since saving re-registers
  // it. This is just a settle window to swallow that one spurious immediate
  // fire; it isn't meant to delay a start that's genuinely still ahead, so it
  // stays short rather than a generous buffer.
  static let registrationSettleSeconds: TimeInterval = 60

  func isPastRegistrationSettleWindow(now: Date = Date()) -> Bool {
    return now.timeIntervalSince(updatedAt) > Self.registrationSettleSeconds
  }

  func nextStartDate(
    now: Date = Date(),
    calendar: Calendar = .current,
    bufferSeconds: TimeInterval = BlockedProfileSchedule.registrationSettleSeconds
  ) -> Date? {
    guard isActive else { return nil }

    let bufferTime = now.addingTimeInterval(bufferSeconds)

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
    let date =
      Calendar.current.date(bySettingHour: hour24, minute: minute, second: 0, of: Date())
      ?? Date()

    let formatter = DateFormatter()
    formatter.locale = Locale.autoupdatingCurrent
    formatter.setLocalizedDateFormatFromTemplate("jm")
    return formatter.string(from: date)
  }
}
