import AlarmKit
import Foundation

// Shared with the widget extension, which draws the alarm on the lock screen.
@available(iOS 26.0, *)
struct CtrusAlarmMetadata: AlarmMetadata {
  var profileId: UUID?
  var profileName: String
}
