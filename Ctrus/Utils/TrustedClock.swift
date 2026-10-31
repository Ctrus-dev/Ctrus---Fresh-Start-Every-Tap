import Foundation

// Measures real time passing without trusting the phone's date, which anyone
// can move forward in Settings. Each instance keeps its own last reading, so
// separate features don't eat into each other's elapsed time.
final class TrustedClock {
  static let emergencyCycle = TrustedClock(key: "emergencyCycle")
  static let recoveryCycle = TrustedClock(key: "recoveryCycle")

  static let maxPoweredOffTime: TimeInterval = 24 * 60 * 60

  private let defaults: UserDefaults
  private let lastWallClockKey: String
  private let lastUptimeKey: String
  private let lastBootSessionKey: String
  private let wallClock: () -> Date
  private let uptime: () -> TimeInterval
  private let bootSession: () -> String?

  init(
    key: String,
    defaults: UserDefaults = .standard,
    wallClock: @escaping () -> Date = Date.init,
    uptime: @escaping () -> TimeInterval = TrustedClock.continuousUptime,
    bootSession: @escaping () -> String? = TrustedClock.currentBootSession
  ) {
    self.defaults = defaults
    self.lastWallClockKey = "trustedClock.\(key).lastWallClock"
    self.lastUptimeKey = "trustedClock.\(key).lastUptime"
    self.lastBootSessionKey = "trustedClock.\(key).lastBootSession"
    self.wallClock = wallClock
    self.uptime = uptime
    self.bootSession = bootSession
  }

  // Not ProcessInfo.systemUptime: that one stops while the phone sleeps, so
  // every night with the screen off would go uncounted. This one keeps
  // running through sleep (like Android's elapsedRealtime) and, like it,
  // ignores the date and only resets on a reboot.
  static func continuousUptime() -> TimeInterval {
    TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000
  }

  // Changes on every boot. The uptime alone can't tell a reboot apart once
  // the phone has been on longer than at the previous reading.
  static func currentBootSession() -> String? {
    var size = 0
    guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else {
      return nil
    }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else { return nil }
    return String(cString: buffer)
  }

  struct Reading {
    let elapsed: TimeInterval
    /// The phone's date moved away from real time by more than
    /// `clockJumpTolerance` since the previous reading.
    let clockJumped: Bool
  }

  static let clockJumpTolerance: TimeInterval = 5 * 60

  /// Real time since the previous call. Whenever it can't be sure, it counts
  /// less, never more.
  func trustedElapsed() -> TimeInterval {
    read().elapsed
  }

  func read() -> Reading {
    let now = wallClock()
    let currentUptime = uptime()
    let currentBootSession = bootSession()
    let lastBootSession = defaults.string(forKey: lastBootSessionKey)

    defer {
      defaults.set(now.timeIntervalSinceReferenceDate, forKey: lastWallClockKey)
      defaults.set(currentUptime, forKey: lastUptimeKey)
      defaults.set(currentBootSession, forKey: lastBootSessionKey)
    }

    guard defaults.object(forKey: lastUptimeKey) != nil,
      defaults.object(forKey: lastWallClockKey) != nil
    else {
      return Reading(elapsed: 0, clockJumped: false)
    }

    let lastUptime = defaults.double(forKey: lastUptimeKey)
    let lastWallClock = Date(
      timeIntervalSinceReferenceDate: defaults.double(forKey: lastWallClockKey))
    let wallClockDelta = now.timeIntervalSince(lastWallClock)

    let rebooted =
      currentUptime < lastUptime
      || (lastBootSession != nil && currentBootSession != nil
        && lastBootSession != currentBootSession)

    // Same boot: the uptime difference is the real time. Any extra the date
    // moved on top of it is a manual date change and is left out.
    if !rebooted {
      let elapsed = currentUptime - lastUptime
      return Reading(
        elapsed: elapsed,
        clockJumped: abs(wallClockDelta - elapsed) > Self.clockJumpTolerance
      )
    }

    // Rebooted: the uptime only covers time since boot. The date is the only
    // hint at how long the phone was off, so it's trusted up to a cap. A long
    // gap isn't flagged: readings can be days apart, so it proves nothing.
    // Only a date earlier than the uptime allows is a sure change.
    let reportedPoweredOffTime = wallClockDelta - currentUptime
    let poweredOffTime = min(max(0, reportedPoweredOffTime), Self.maxPoweredOffTime)
    return Reading(
      elapsed: max(0, currentUptime + poweredOffTime),
      clockJumped: reportedPoweredOffTime < -Self.clockJumpTolerance
    )
  }
}
