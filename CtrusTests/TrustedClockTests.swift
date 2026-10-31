import XCTest

@testable import Ctrus

final class TrustedClockTests: XCTestCase {
  private var defaults: UserDefaults!
  private var wallClock = Date(timeIntervalSinceReferenceDate: 1_000_000)
  private var uptime: TimeInterval = 10_000
  private var bootSession = "boot-1"

  private let day: TimeInterval = 24 * 60 * 60

  override func setUp() {
    super.setUp()
    defaults = UserDefaults(suiteName: "TrustedClockTests")
    defaults.removePersistentDomain(forName: "TrustedClockTests")
  }

  private func makeClock() -> TrustedClock {
    TrustedClock(
      key: "test",
      defaults: defaults,
      wallClock: { self.wallClock },
      uptime: { self.uptime },
      bootSession: { self.bootSession }
    )
  }

  func testGivenFirstReading_WhenAsked_ThenCountsNothing() {
    XCTAssertEqual(makeClock().trustedElapsed(), 0)
  }

  func testGivenNoReboot_WhenTimePasses_ThenCountsUptime() {
    let clock = makeClock()
    _ = clock.trustedElapsed()

    wallClock += 3_600
    uptime += 3_600

    XCTAssertEqual(clock.trustedElapsed(), 3_600, accuracy: 0.001)
  }

  func testGivenNoReboot_WhenDateMovedForward30Days_ThenOnlyRealTimeCounts() {
    let clock = makeClock()
    _ = clock.trustedElapsed()

    wallClock += 30 * day
    uptime += 60

    XCTAssertEqual(clock.trustedElapsed(), 60, accuracy: 0.001)
  }

  func testGivenReboot_WhenDateMovedForward30Days_ThenCountsAtMost24Hours() {
    let clock = makeClock()
    _ = clock.trustedElapsed()

    wallClock += 30 * day
    uptime = 120

    XCTAssertEqual(clock.trustedElapsed(), 120 + day, accuracy: 0.001)
  }

  func testGivenReboot_WhenPhoneWasOffBriefly_ThenCountsTheTimeOff() {
    let clock = makeClock()
    _ = clock.trustedElapsed()

    wallClock += 3_600
    uptime = 600

    XCTAssertEqual(clock.trustedElapsed(), 3_600, accuracy: 0.001)
  }

  func testGivenReboot_WhenDateMovedBack_ThenNeverNegative() {
    let clock = makeClock()
    _ = clock.trustedElapsed()

    wallClock -= 10 * day
    uptime = 300

    XCTAssertEqual(clock.trustedElapsed(), 300, accuracy: 0.001)
  }

  func testGivenSeparateKeys_WhenRead_ThenTheyDontShareReadings() {
    let first = makeClock()
    let second = TrustedClock(
      key: "other", defaults: defaults, wallClock: { self.wallClock }, uptime: { self.uptime })
    _ = first.trustedElapsed()
    _ = second.trustedElapsed()

    wallClock += 100
    uptime += 100
    _ = first.trustedElapsed()

    XCTAssertEqual(second.trustedElapsed(), 100, accuracy: 0.001)
  }

  func testGivenRebootDaysAfterLastReading_WhenRead_ThenNoClockJump() {
    let clock = makeClock()
    _ = clock.read()

    wallClock += 3 * day
    uptime = 600
    bootSession = "boot-2"

    XCTAssertFalse(clock.read().clockJumped)
  }

  func testGivenRebootWithLongerUptime_WhenRead_ThenTreatedAsReboot() {
    let clock = makeClock()
    _ = clock.read()

    wallClock += 3 * day
    uptime = 20_000
    bootSession = "boot-2"

    let reading = clock.read()
    XCTAssertFalse(reading.clockJumped)
    XCTAssertEqual(reading.elapsed, 20_000 + day, accuracy: 0.001)
  }

  func testGivenNoReboot_WhenDateMovedForward_ThenClockJumped() {
    let clock = makeClock()
    _ = clock.read()

    wallClock += day
    uptime += 60

    XCTAssertTrue(clock.read().clockJumped)
  }
}
