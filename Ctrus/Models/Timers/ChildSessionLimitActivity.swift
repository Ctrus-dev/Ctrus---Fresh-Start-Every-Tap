import DeviceActivity
import OSLog

private let log = Logger(subsystem: "com.Ctrus.monitor", category: ChildSessionLimitActivity.id)

// Wakes the monitor when a child mode session's automatic end is due; the
// decision itself (and re-arming it if the date was moved) is in
// ChildSessionLimit.
class ChildSessionLimitActivity: TimerActivity {
  static var id: String = ChildSessionLimit.activityId

  func start(for profile: SharedData.ProfileSnapshot) {
    // The interval starts in the past so it can be registered at all; only
    // its end matters.
  }

  func stop(for profile: SharedData.ProfileSnapshot) {
    log.info("Child mode limit check for \(profile.id.uuidString)")
    ChildSessionLimit.check()
  }
}
