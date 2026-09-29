import Foundation

enum SessionTimeCalculator {
  private static let timerStrategyIds: Set<String> = [
    NFCTimerBlockingStrategy.id,
    ShortcutTimerBlockingStrategy.id,
  ]

  static func elapsedFocusTime(
    for session: BlockedProfileSession,
    at date: Date = Date()
  ) -> TimeInterval {
    let rawElapsedTime = date.timeIntervalSince(session.startTime)
    let breakDuration = calculateBreakDuration(for: session, at: date)
    return max(0, rawElapsedTime - breakDuration)
  }

  static func displayedTime(
    for session: BlockedProfileSession,
    elapsedFocusTime: TimeInterval? = nil,
    at date: Date = Date()
  ) -> TimeInterval {
    if let expectedEndTime = expectedEndTime(for: session) {
      return max(0, expectedEndTime.timeIntervalSince(date))
    }

    return elapsedFocusTime ?? self.elapsedFocusTime(for: session, at: date)
  }

  static func expectedEndTime(for session: BlockedProfileSession) -> Date? {
    if let pauseStartTime = session.pauseStartTime, session.isPauseActive {
      return pauseStartTime.addingTimeInterval(pauseDurationInSeconds(for: session.blockedProfile))
    }

    if let breakStartTime = session.breakStartTime, session.isBreakActive {
      if session.blockedProfile.allowMultipleBreaks {
        let remainingAllowanceAtBreakStart = session.remainingBreakAllowance(at: breakStartTime)
        return breakStartTime.addingTimeInterval(remainingAllowanceAtBreakStart)
      }

      return breakStartTime.addingTimeInterval(session.totalBreakAllowanceInSeconds)
    }

    // Only a schedule with a fixed duration counts down. An indefinite one runs
    // until the Ctrus is scanned, so it has no end to count towards and the
    // clock counts up instead.
    if isScheduledSession(session), let schedule = session.blockedProfile.schedule {
      guard let durationInSeconds = schedule.automaticEndDurationInSeconds else { return nil }
      return session.startTime.addingTimeInterval(durationInSeconds)
    }

    if isTimerSession(session), let timerDuration = timerDurationInSeconds(for: session) {
      return session.startTime.addingTimeInterval(timerDuration)
    }

    return nil
  }

  static func isTimerSession(_ session: BlockedProfileSession) -> Bool {
    Self.timerStrategyIds.contains(session.tag)
      || Self.timerStrategyIds.contains(session.blockedProfile.blockingStrategyId ?? "")
  }

  static func timerDurationInSeconds(for session: BlockedProfileSession) -> TimeInterval? {
    guard let strategyData = session.blockedProfile.strategyData else {
      return nil
    }

    let timerData = StrategyTimerData.toStrategyTimerData(from: strategyData)
    return TimeInterval(timerData.durationInMinutes * 60)
  }

  private static func isScheduledSession(_ session: BlockedProfileSession) -> Bool {
    // Checking the tag format instead of the strategy would miss sessions
    // started manually (Schedule mode still allows "hold to start" in app,
    // which tags with the strategy id, not the profile's UUID like an
    // automatic start does) — those still need the fixed-duration countdown.
    session.blockedProfile.schedule?.isActive == true
      && session.blockedProfile.blockingStrategyId == ScheduleBlockingStrategy.id
  }

  private static func pauseDurationInSeconds(for profile: BlockedProfiles) -> TimeInterval {
    guard let strategyData = profile.strategyData else {
      return TimeInterval(15 * 60)
    }

    let pauseData = StrategyPauseTimerData.toStrategyPauseTimerData(from: strategyData)
    return TimeInterval(pauseData.pauseDurationInMinutes * 60)
  }

  private static func calculateBreakDuration(
    for session: BlockedProfileSession,
    at date: Date
  ) -> TimeInterval {
    if session.blockedProfile.allowMultipleBreaks {
      return session.usedBreakDurationIncludingActiveBreak(at: date)
    }

    guard let breakStartTime = session.breakStartTime else {
      return 0
    }

    if let breakEndTime = session.breakEndTime {
      return max(0, breakEndTime.timeIntervalSince(breakStartTime))
    }

    if session.isBreakActive {
      return max(0, date.timeIntervalSince(breakStartTime))
    }

    return 0
  }
}
