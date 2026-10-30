import AppIntents

/// Runs when the alarm is slid away: the system silences it and opens the
/// app, where the sound carries on until the Ctrus is tapped.
@available(iOS 26.0, *)
struct OpenAlarmProfileIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Open the alarm's profile"
  static var openAppWhenRun = true
  static var isDiscoverable = false

  @Parameter(title: "Profile ID") var profileId: String

  init() {}

  init(profileId: String) {
    self.profileId = profileId
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    WakeAlarmManager.shared.alarmOpenedApp(profileId: profileId)
    return .result()
  }
}
