import AppIntents

/// Runs from the alarm's Snooze button, without opening the app: holds the
/// alarm and its spares back until the snooze is over.
@available(iOS 26.0, *)
struct SnoozeAlarmProfileIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Snooze the alarm"
  static var openAppWhenRun = false
  static var isDiscoverable = false

  @Parameter(title: "Profile ID") var profileId: String

  init() {}

  init(profileId: String) {
    self.profileId = profileId
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    if let profileId = UUID(uuidString: profileId) {
      await WakeAlarmManager.shared.snooze(profileId: profileId)
    }
    return .result()
  }
}
