import XCTest

@testable import Ctrus

final class SessionTimeCalculatorTests: XCTestCase {
  func testTimerSessionDisplaysRemainingTime() {
    let startTime = Date(timeIntervalSinceReferenceDate: 1_000)
    let profile = makeProfile(strategyId: NFCTimerBlockingStrategy.id, durationInMinutes: 60)
    let session = BlockedProfileSession(
      tag: NFCTimerBlockingStrategy.id,
      blockedProfile: profile
    )
    session.startTime = startTime

    let currentTime = startTime.addingTimeInterval(15 * 60)
    let elapsedTime = SessionTimeCalculator.elapsedFocusTime(for: session, at: currentTime)
    let displayTime = SessionTimeCalculator.displayedTime(
      for: session,
      elapsedFocusTime: elapsedTime,
      at: currentTime
    )

    XCTAssertEqual(elapsedTime, 15 * 60, accuracy: 0.1)
    XCTAssertEqual(displayTime, 45 * 60, accuracy: 0.1)
  }

  func testManualSessionDisplaysElapsedTime() {
    let startTime = Date(timeIntervalSinceReferenceDate: 1_000)
    let profile = makeProfile(strategyId: ManualBlockingStrategy.id)
    let session = BlockedProfileSession(
      tag: ManualBlockingStrategy.id,
      blockedProfile: profile
    )
    session.startTime = startTime

    let currentTime = startTime.addingTimeInterval(20 * 60)
    let displayTime = SessionTimeCalculator.displayedTime(for: session, at: currentTime)

    XCTAssertEqual(displayTime, 20 * 60, accuracy: 0.1)
  }

  func testTimerDisplayMatchesLiveActivityEndTimeAfterBreak() {
    let startTime = Date(timeIntervalSinceReferenceDate: 1_000)
    let profile = makeProfile(
      strategyId: NFCTimerBlockingStrategy.id,
      durationInMinutes: 60,
      enableBreaks: true
    )
    let session = BlockedProfileSession(
      tag: NFCTimerBlockingStrategy.id,
      blockedProfile: profile
    )
    session.startTime = startTime
    session.breakStartTime = startTime.addingTimeInterval(10 * 60)
    session.breakEndTime = startTime.addingTimeInterval(20 * 60)

    let currentTime = startTime.addingTimeInterval(30 * 60)
    let elapsedTime = SessionTimeCalculator.elapsedFocusTime(for: session, at: currentTime)
    let displayTime = SessionTimeCalculator.displayedTime(
      for: session,
      elapsedFocusTime: elapsedTime,
      at: currentTime
    )

    XCTAssertEqual(elapsedTime, 20 * 60, accuracy: 0.1)
    XCTAssertEqual(displayTime, 30 * 60, accuracy: 0.1)
    XCTAssertEqual(
      SessionTimeCalculator.expectedEndTime(for: session),
      startTime.addingTimeInterval(60 * 60)
    )
  }

  func testSingleBreakIsUnavailableAfterItEnds() {
    let startTime = Date(timeIntervalSinceReferenceDate: 1_000)
    let profile = makeProfile(
      strategyId: ManualBlockingStrategy.id,
      enableBreaks: true,
      breakTimeInMinutes: 15,
      allowMultipleBreaks: false
    )
    let session = BlockedProfileSession(
      tag: ManualBlockingStrategy.id,
      blockedProfile: profile
    )
    session.startTime = startTime
    session.breakStartTime = startTime.addingTimeInterval(5 * 60)
    session.breakEndTime = startTime.addingTimeInterval(8 * 60)

    XCTAssertFalse(session.isBreakAvailable)
    XCTAssertEqual(
      SessionTimeCalculator.elapsedFocusTime(
        for: session,
        at: startTime.addingTimeInterval(10 * 60)
      ),
      7 * 60,
      accuracy: 0.1
    )
  }

  func testReusableBreakStoppedEarlyLeavesRemainingAllowance() {
    let startTime = Date(timeIntervalSinceReferenceDate: 1_000)
    let profile = makeProfile(
      strategyId: ManualBlockingStrategy.id,
      enableBreaks: true,
      breakTimeInMinutes: 15,
      allowMultipleBreaks: true
    )
    let session = BlockedProfileSession(
      tag: ManualBlockingStrategy.id,
      blockedProfile: profile
    )
    session.startTime = startTime
    session.breakStartTime = startTime.addingTimeInterval(5 * 60)
    session.breakEndTime = startTime.addingTimeInterval(8 * 60)
    session.usedBreakDurationInSeconds = 3 * 60

    XCTAssertTrue(session.isBreakAvailable)
    XCTAssertEqual(session.remainingBreakAllowance(), 12 * 60, accuracy: 0.1)
  }

  func testReusableBreakDisplaysRemainingAllowanceDuringSecondBreak() {
    let startTime = Date(timeIntervalSinceReferenceDate: 1_000)
    let profile = makeProfile(
      strategyId: ManualBlockingStrategy.id,
      enableBreaks: true,
      breakTimeInMinutes: 15,
      allowMultipleBreaks: true
    )
    let session = BlockedProfileSession(
      tag: ManualBlockingStrategy.id,
      blockedProfile: profile
    )
    session.startTime = startTime
    session.usedBreakDurationInSeconds = 3 * 60
    session.breakStartTime = startTime.addingTimeInterval(10 * 60)

    let currentTime = startTime.addingTimeInterval(12 * 60)
    let elapsedTime = SessionTimeCalculator.elapsedFocusTime(for: session, at: currentTime)
    let displayTime = SessionTimeCalculator.displayedTime(
      for: session,
      elapsedFocusTime: elapsedTime,
      at: currentTime
    )

    XCTAssertEqual(elapsedTime, 7 * 60, accuracy: 0.1)
    XCTAssertEqual(displayTime, 10 * 60, accuracy: 0.1)
  }

  func testReusableBreakUnavailableWhenAllowanceIsExhausted() {
    let profile = makeProfile(
      strategyId: ManualBlockingStrategy.id,
      enableBreaks: true,
      breakTimeInMinutes: 15,
      allowMultipleBreaks: true
    )
    let session = BlockedProfileSession(
      tag: ManualBlockingStrategy.id,
      blockedProfile: profile
    )
    session.usedBreakDurationInSeconds = 15 * 60

    XCTAssertFalse(session.isBreakAvailable)
    XCTAssertEqual(session.remainingBreakAllowance(), 0, accuracy: 0.1)
  }

  func testReusableBreakAllowanceResetsForNewSession() {
    let profile = makeProfile(
      strategyId: ManualBlockingStrategy.id,
      enableBreaks: true,
      breakTimeInMinutes: 15,
      allowMultipleBreaks: true
    )
    let session = BlockedProfileSession(
      tag: ManualBlockingStrategy.id,
      blockedProfile: profile
    )

    XCTAssertTrue(session.isBreakAvailable)
    XCTAssertEqual(session.remainingBreakAllowance(), 15 * 60, accuracy: 0.1)
  }

  func testIndefiniteScheduledSessionCountsUp() {
    let startTime = Date(timeIntervalSinceReferenceDate: 1_000)
    let profile = makeProfile(
      strategyId: ScheduleBlockingStrategy.id,
      schedule: makeSchedule(durationInHours: nil)
    )
    let session = BlockedProfileSession(
      tag: profile.id.uuidString,
      blockedProfile: profile
    )
    session.startTime = startTime

    let currentTime = startTime.addingTimeInterval(90 * 60)

    XCTAssertNil(SessionTimeCalculator.expectedEndTime(for: session))
    XCTAssertEqual(
      SessionTimeCalculator.displayedTime(for: session, at: currentTime),
      90 * 60,
      accuracy: 0.1
    )
  }

  func testScheduledSessionWithDurationCountsDown() {
    let startTime = Date(timeIntervalSinceReferenceDate: 1_000)
    let profile = makeProfile(
      strategyId: ScheduleBlockingStrategy.id,
      schedule: makeSchedule(durationInHours: 2)
    )
    let session = BlockedProfileSession(
      tag: profile.id.uuidString,
      blockedProfile: profile
    )
    session.startTime = startTime

    let currentTime = startTime.addingTimeInterval(30 * 60)

    XCTAssertEqual(
      SessionTimeCalculator.expectedEndTime(for: session),
      startTime.addingTimeInterval(2 * 60 * 60)
    )
    XCTAssertEqual(
      SessionTimeCalculator.displayedTime(for: session, at: currentTime),
      90 * 60,
      accuracy: 0.1
    )
  }

  func testScheduleEndComponentsFollowDuration() {
    var schedule = makeSchedule(durationInHours: nil)
    XCTAssertFalse(schedule.hasAutomaticEnd)
    XCTAssertEqual(schedule.endComponents.hour, 23)
    XCTAssertEqual(schedule.endComponents.minute, 59)

    schedule.startHour = 22
    schedule.startMinute = 30
    schedule.durationInHours = 4

    XCTAssertTrue(schedule.hasAutomaticEnd)
    XCTAssertEqual(schedule.endComponents.hour, 2)
    XCTAssertEqual(schedule.endComponents.minute, 30)
  }

  private func makeSchedule(durationInHours: Int?) -> BlockedProfileSchedule {
    BlockedProfileSchedule(
      days: [.monday],
      startHour: 9,
      startMinute: 0,
      durationInHours: durationInHours
    )
  }

  private func makeProfile(
    strategyId: String,
    durationInMinutes: Int? = nil,
    enableBreaks: Bool = false,
    breakTimeInMinutes: Int = 15,
    allowMultipleBreaks: Bool = false,
    schedule: BlockedProfileSchedule? = nil
  ) -> BlockedProfiles {
    let strategyData = durationInMinutes.flatMap {
      StrategyTimerData.toData(
        from: StrategyTimerData(durationInMinutes: $0, hideStopButton: false)
      )
    }

    return BlockedProfiles(
      name: "Focus",
      blockingStrategyId: strategyId,
      strategyData: strategyData,
      enableBreaks: enableBreaks,
      breakTimeInMinutes: breakTimeInMinutes,
      allowMultipleBreaks: allowMultipleBreaks,
      schedule: schedule
    )
  }
}
