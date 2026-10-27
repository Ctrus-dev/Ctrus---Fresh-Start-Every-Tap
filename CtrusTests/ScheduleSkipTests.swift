import XCTest

@testable import Ctrus

final class ScheduleSkipTests: XCTestCase {
  private var calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Lisbon")!
    return calendar
  }()

  // Monday, 2 Nov 2026
  private func date(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    calendar.date(
      from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
  }

  private let schedule = BlockedProfileSchedule(
    days: [.monday, .wednesday, .friday],
    startHour: 22,
    startMinute: 50,
    durationInHours: 2
  )

  func testGivenSkipNext_WhenThatOccurrenceStarts_ThenItIsSkippedAndTheNextIsNot() {
    let skip = ScheduleSkip(skipNextOccurrence: date(2, 22, 50))

    XCTAssertTrue(skip.skips(occurrenceStartingAt: date(2, 22, 51), calendar: calendar))
    XCTAssertFalse(skip.skips(occurrenceStartingAt: date(4, 22, 50), calendar: calendar))
  }

  func testGivenSkipUntil_WhenChecked_ThenSkipsThroughThatDayInclusive() {
    let skip = ScheduleSkip(skipUntil: date(6, 0, 0))

    XCTAssertTrue(skip.skips(occurrenceStartingAt: date(6, 22, 50), calendar: calendar))
    XCTAssertFalse(skip.skips(occurrenceStartingAt: date(9, 22, 50), calendar: calendar))
  }

  func testGivenSkipUntil_WhenTheDayAfterComes_ThenItExpires() {
    let skip = ScheduleSkip(skipUntil: date(6, 0, 0))

    XCTAssertTrue(skip.isActive(now: date(6, 23, 59), calendar: calendar))
    XCTAssertFalse(skip.isActive(now: date(7, 0, 0), calendar: calendar))
    XCTAssertNil(skip.clearingExpired(now: date(7, 0, 1), calendar: calendar).skipUntil)
  }

  func testGivenSkipNext_WhenItsDayEnds_ThenItExpires() {
    let skip = ScheduleSkip(skipNextOccurrence: date(2, 22, 50))

    XCTAssertTrue(skip.isActive(now: date(2, 23, 30), calendar: calendar))
    XCTAssertFalse(skip.isActive(now: date(3, 0, 1), calendar: calendar))
  }

  func testGivenCountingUntilAFriday_WhenTodaysSessionAlreadyStarted_ThenItIsNotCounted() {
    let starts = schedule.upcomingOccurrenceStarts(
      from: date(2, 23, 0), throughEndOf: date(6), calendar: calendar)

    // Wednesday and Friday — Monday's already began.
    XCTAssertEqual(starts, [date(4, 22, 50), date(6, 22, 50)])
  }

  func testGivenCountingUntilATuesday_WhenOnlyTodaysStartedSessionFalls_ThenNoneAreCounted() {
    let starts = schedule.upcomingOccurrenceStarts(
      from: date(2, 23, 0), throughEndOf: date(3), calendar: calendar)

    XCTAssertTrue(starts.isEmpty)
  }

  func testGivenReminderTimeHasPassed_WhenLookingUpTheDaysNextOccurrence_ThenItIsNextWeek() {
    let start = schedule.nextOccurrenceStart(
      on: .monday, remindingMinutesBefore: 5, after: date(2, 22, 46), calendar: calendar)

    XCTAssertEqual(start, date(9, 22, 50))
  }

  func testGivenReminderStillAhead_WhenLookingUpTheDaysNextOccurrence_ThenItIsToday() {
    let start = schedule.nextOccurrenceStart(
      on: .monday, remindingMinutesBefore: 5, after: date(2, 22, 0), calendar: calendar)

    XCTAssertEqual(start, date(2, 22, 50))
  }

  func testGivenSkippedOccurrences_WhenFindingTheNextStart_ThenTheFirstUnskippedOneIsShown() {
    let skip = ScheduleSkip(skipNextOccurrence: date(2, 22, 50), skipUntil: date(6))

    let nextStart = schedule.nextStartDate(
      now: date(2, 9), calendar: calendar, bufferSeconds: 0, skip: skip)

    XCTAssertEqual(nextStart, date(9, 22, 50))
  }

  func testGivenSkipUntil30DaysAhead_WhenFindingTheNextStart_ThenItLooksPastTheSkip() {
    let skip = ScheduleSkip(skipUntil: date(30))

    let nextStart = schedule.nextStartDate(
      now: date(2, 9), calendar: calendar, bufferSeconds: 0, skip: skip)

    // Monday 30 Nov is still skipped; Wednesday 2 Dec is the first back.
    XCTAssertEqual(
      nextStart,
      calendar.date(from: DateComponents(year: 2026, month: 12, day: 2, hour: 22, minute: 50)))
  }

  func testGivenSkipNotAllowed_WhenReadFromSnapshot_ThenNothingIsSkipped() {
    var snapshot = BlockedProfiles.getSnapshot(for: BlockedProfiles(name: "Test"))
    snapshot.skipUntil = date(6)
    snapshot.allowSkip = false

    XCTAssertEqual(snapshot.scheduleSkip, ScheduleSkip())
  }
}
