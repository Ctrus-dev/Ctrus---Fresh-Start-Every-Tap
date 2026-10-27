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
  private let wallClock: () -> Date
  private let uptime: () -> TimeInterval

  init(
    key: String,
    defaults: UserDefaults = .standard,
    wallClock: @escaping () -> Date = Date.init,
    uptime: @escaping () -> TimeInterval = TrustedClock.continuousUptime
  ) {
    self.defaults = defaults
    self.lastWallClockKey = "trustedClock.\(key).lastWallClock"
    self.lastUptimeKey = "trustedClock.\(key).lastUptime"
    self.wallClock = wallClock
    self.uptime = uptime
  }

  // Not ProcessInfo.systemUptime: that one stops while the phone sleeps, so
  // every night with the screen off would go uncounted. This one keeps
  // running through sleep (like Android's elapsedRealtime) and, like it,
  // ignores the date and only resets on a reboot.
  static func continuousUptime() -> TimeInterval {
    TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000
  }

  /// Real time since the previous call. Whenever it can't be sure, it counts
  /// less, never more.
  func trustedElapsed() -> TimeInterval {
    let now = wallClock()
    let currentUptime = uptime()

    defer {
      defaults.set(now.timeIntervalSinceReferenceDate, forKey: lastWallClockKey)
      defaults.set(currentUptime, forKey: lastUptimeKey)
    }

    guard defaults.object(forKey: lastUptimeKey) != nil,
      defaults.object(forKey: lastWallClockKey) != nil
    else {
      return 0
    }

    let lastUptime = defaults.double(forKey: lastUptimeKey)
    let lastWallClock = Date(
      timeIntervalSinceReferenceDate: defaults.double(forKey: lastWallClockKey))

    // Same boot: the uptime difference is the real time. Any extra the date
    // moved on top of it is a manual date change and is left out.
    if currentUptime >= lastUptime {
      return currentUptime - lastUptime
    }

    // Rebooted: the uptime only covers time since boot. The date is the only
    // hint at how long the phone was off, so it's trusted up to a cap.
    let wallClockDelta = now.timeIntervalSince(lastWallClock)
    let poweredOffTime = min(max(0, wallClockDelta - currentUptime), Self.maxPoweredOffTime)
    return max(0, currentUptime + poweredOffTime)
  }
}
