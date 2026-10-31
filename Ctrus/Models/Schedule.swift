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

  // Alarm mode only. Optional so schedules saved before it still decode;
  // read through `alarmTime` and `alarmSoundId`, which fill in the defaults.
  var alarmHour: Int?
  var alarmMinute: Int?
  var alarmSound: String?
  var snoozeMinutes: Int?

  static let availableSnoozeMinutes = Array(1...15)
  static let defaultSnoozeMinutes = 9

  /// The tones in `alarm_sounds/`, by file name without the extension.
  static let alarmToneIds = [
    "ctrus_urgent",
    "ctrus_morning",
    "ctrus_lumen",
    "ctrus_pulsar",
    "ctrus_orbit",
    "ctrus_lagoon",
    "ctrus_spark",
    "ctrus_waves",
    "ctrus_daybreak",
    "ctrus_musicbox",
    "ctrus_rally",
  ]
  static let defaultAlarmSound = "ctrus_morning"
  static let vibrateAlarmSound = "vibrate"

  var alarmTime: (hour: Int, minute: Int) {
    (alarmHour ?? 7, alarmMinute ?? 0)
  }

  /// Falls back to the default for a sound that's no longer offered, like
  /// the system's own alarm sound from before the Ctrus tones.
  var alarmSoundId: String {
    guard let alarmSound,
      alarmSound == Self.vibrateAlarmSound || Self.alarmToneIds.contains(alarmSound)
    else {
      return Self.defaultAlarmSound
    }
    return alarmSound
  }

  var alarmSnoozeMinutes: Int {
    get { snoozeMinutes ?? Self.defaultSnoozeMinutes }
    set { snoozeMinutes = newValue }
  }

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
    let startMinutes = startHour * 60 + startMinute

    guard let durationInHours else {
      // DeviceActivity refuses windows under 15 minutes, so a late start runs
      // the window past midnight instead.
      let endMinutes = max(23 * 60 + 59, startMinutes + 15) % (24 * 60)
      return (endMinutes / 60, endMinutes % 60)
    }

    let minutesFromMidnight = (startMinutes + durationInHours * 60) % (24 * 60)
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

  /// Alarm mode's summary: the end time takes the duration's place.
  var alarmSummaryText: String {
    guard isActive else { return String(localized: "No Schedule Set") }

    let daysSummary =
      days
      .sorted { $0.rawValue < $1.rawValue }
      .map { $0.shortLabel }
      .joined(separator: " ")

    return "\(daysSummary) · \(alarmTimeRangeText)"
  }

  var alarmTimeRangeText: String {
    let start = formattedTimeString(hour24: startHour, minute: startMinute)
    let end = formattedTimeString(hour24: alarmTime.hour, minute: alarmTime.minute)
    return "\(start) → \(end)"
  }

  var hasValidAlarmTime: Bool {
    alarmTime.hour != startHour || alarmTime.minute != startMinute
  }

  /// When the alarm rings for a session that started at `start`: the first
  /// end time after it, so an end at or before the start is the next day.
  /// Matched on the wall clock, so a daylight saving change that night
  /// doesn't move it.
  func alarmDate(after start: Date, calendar: Calendar = .current) -> Date? {
    calendar.nextDate(
      after: start,
      matching: DateComponents(hour: alarmTime.hour, minute: alarmTime.minute, second: 0),
      matchingPolicy: .nextTime
    )
  }

  /// The occurrence under way whose alarm hasn't finished ringing, give or
  /// take `grace`. One that started before the schedule was last saved never
  /// ran, as the Screen Time extension ignores it too.
  func currentAlarmOccurrenceStart(
    now: Date = Date(),
    grace: TimeInterval,
    skip: ScheduleSkip = ScheduleSkip(),
    calendar: Calendar = .current
  ) -> Date? {
    guard isActive else { return nil }

    for daysBack in 0...1 {
      guard
        let day = calendar.date(byAdding: .day, value: -daysBack, to: calendar.startOfDay(for: now)),
        let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)),
        days.contains(weekday),
        let start = calendar.date(
          bySettingHour: startHour, minute: startMinute, second: 0, of: day),
        start <= now,
        isPastRegistrationSettleWindow(now: start),
        !skip.skips(occurrenceStartingAt: start, calendar: calendar),
        let alarmDate = alarmDate(after: start, calendar: calendar),
        now < alarmDate.addingTimeInterval(grace)
      else {
        continue
      }
      return start
    }

    return nil
  }

  /// The days the alarm rings on, which move to the next day when the end
  /// time is at or before the start.
  var alarmDays: [Weekday] {
    let endsNextDay =
      alarmTime.hour * 60 + alarmTime.minute <= startHour * 60 + startMinute
    guard endsNextDay else { return days }

    return days.compactMap { Weekday(rawValue: $0.rawValue % 7 + 1) }
  }

  /// "Mon–Fri", or "Mon, Wed, Sat" when the days aren't in a row.
  func alarmDaysText(calendar: Calendar = .current) -> String {
    let symbols = calendar.shortWeekdaySymbols
    let ringDays = Set(alarmDays.map(\.rawValue))
    let week = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }

    var runs: [[Int]] = []
    for day in week where ringDays.contains(day) {
      if let last = runs.last?.last, week.firstIndex(of: last)! + 1 == week.firstIndex(of: day)! {
        runs[runs.count - 1].append(day)
      } else {
        runs.append([day])
      }
    }

    return
      runs
      .map { run in
        run.count >= 3
          ? "\(symbols[run.first! - 1])–\(symbols[run.last! - 1])"
          : run.map { symbols[$0 - 1] }.joined(separator: ", ")
      }
      .joined(separator: ", ")
  }

  var alarmTimeText: String {
    formattedTimeString(hour24: alarmTime.hour, minute: alarmTime.minute)
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
    bufferSeconds: TimeInterval = BlockedProfileSchedule.registrationSettleSeconds,
    skip: ScheduleSkip = ScheduleSkip()
  ) -> Date? {
    guard isActive else { return nil }

    let bufferTime = now.addingTimeInterval(bufferSeconds)

    // A week is enough to reach every scheduled day; the extra weeks are for
    // looking past a skip, which can run up to 30 days ahead.
    for daysAhead in 0..<42 {
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

      if scheduleStartTime >= bufferTime
        && !skip.skips(occurrenceStartingAt: scheduleStartTime, calendar: calendar)
      {
        return scheduleStartTime
      }
    }

    return nil
  }

  func nextStartMessage(
    now: Date = Date(),
    calendar: Calendar = .current,
    includePrefix: Bool = true,
    skip: ScheduleSkip = ScheduleSkip()
  ) -> String? {
    guard let nextStart = nextStartDate(now: now, calendar: calendar, skip: skip) else {
      return nil
    }

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

extension BlockedProfileSchedule {
  /// Starts of the occurrences that haven't begun yet, from `now` up to the
  /// end of `lastDay`.
  func upcomingOccurrenceStarts(
    from now: Date = Date(),
    throughEndOf lastDay: Date,
    calendar: Calendar = .current
  ) -> [Date] {
    guard isActive else { return [] }

    var starts: [Date] = []
    var day = calendar.startOfDay(for: now)
    let lastDayStart = calendar.startOfDay(for: lastDay)

    while day <= lastDayStart {
      if let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)),
        days.contains(weekday),
        let start = calendar.date(
          bySettingHour: startHour, minute: startMinute, second: 0, of: day),
        start > now
      {
        starts.append(start)
      }

      guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
      day = nextDay
    }

    return starts
  }

  /// The first occurrence of `weekday` whose 5-minute reminder is still
  /// ahead — the one a repeating reminder for that day would fire for next.
  func nextOccurrenceStart(
    on weekday: Weekday,
    remindingMinutesBefore minutesBefore: Int,
    after now: Date = Date(),
    calendar: Calendar = .current
  ) -> Date? {
    let today = calendar.startOfDay(for: now)

    for daysAhead in 0...7 {
      guard let day = calendar.date(byAdding: .day, value: daysAhead, to: today),
        calendar.component(.weekday, from: day) == weekday.rawValue,
        let start = calendar.date(
          bySettingHour: startHour, minute: startMinute, second: 0, of: day)
      else {
        continue
      }

      if start.addingTimeInterval(TimeInterval(-minutesBefore * 60)) > now {
        return start
      }
    }

    return nil
  }
}

/// Occurrences of a schedule the person chose to skip, without touching the
/// schedule itself.
struct ScheduleSkip: Equatable {
  /// Start of the one occurrence to skip.
  var skipNextOccurrence: Date?
  /// Every occurrence up to and including this day is skipped.
  var skipUntil: Date?

  func skips(occurrenceStartingAt start: Date, calendar: Calendar = .current) -> Bool {
    if let skipNextOccurrence, calendar.isDate(skipNextOccurrence, inSameDayAs: start) {
      return true
    }

    if let skipUntil,
      calendar.startOfDay(for: start) <= calendar.startOfDay(for: skipUntil)
    {
      return true
    }

    return false
  }

  // The single skip is kept until that whole day is over rather than just
  // past its start time — the monitor can fire a little late, and must still
  // find it there when it does.
  func isNextOccurrenceSkipActive(now: Date = Date(), calendar: Calendar = .current) -> Bool {
    guard let skipNextOccurrence,
      let dayAfter = calendar.date(
        byAdding: .day, value: 1, to: calendar.startOfDay(for: skipNextOccurrence))
    else {
      return false
    }

    return now < dayAfter
  }

  func isSkipUntilActive(now: Date = Date(), calendar: Calendar = .current) -> Bool {
    guard let skipUntil else { return false }
    return calendar.startOfDay(for: now) <= calendar.startOfDay(for: skipUntil)
  }

  func isActive(now: Date = Date(), calendar: Calendar = .current) -> Bool {
    isNextOccurrenceSkipActive(now: now, calendar: calendar)
      || isSkipUntilActive(now: now, calendar: calendar)
  }

  func clearingExpired(now: Date = Date(), calendar: Calendar = .current) -> ScheduleSkip {
    ScheduleSkip(
      skipNextOccurrence: isNextOccurrenceSkipActive(now: now, calendar: calendar)
        ? skipNextOccurrence : nil,
      skipUntil: isSkipUntilActive(now: now, calendar: calendar) ? skipUntil : nil
    )
  }
}
