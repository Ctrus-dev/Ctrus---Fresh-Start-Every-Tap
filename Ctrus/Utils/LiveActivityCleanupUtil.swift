import ActivityKit
import Foundation

/// Ends the session Live Activities earlier versions started. There's no Live
/// Activity any more, so nothing else would close one still showing in the
/// Dynamic Island.
enum LiveActivityCleanupUtil {
  static func endLeftoverActivities() {
    Task {
      for activity in Activity<CtrusWidgetAttributes>.activities {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
    }
  }
}

/// The attributes those activities were started with, kept only to find them.
struct CtrusWidgetAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var startTime: Date
    var expectedEndTime: Date?
    var isBreakActive: Bool = false
    var breakStartTime: Date?
    var breakEndTime: Date?
    var usedBreakDurationInSeconds: TimeInterval = 0
    var isPauseActive: Bool = false
    var pauseStartTime: Date?
    var pauseEndTime: Date?
  }

  var name: String
  var message: String
}
