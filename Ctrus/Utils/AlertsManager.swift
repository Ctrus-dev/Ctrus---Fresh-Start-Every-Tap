import Combine
import FamilyControls
import Foundation

class AlertsManager: ObservableObject {
  static let shared = AlertsManager()

  @Published var alerts: [HomeAlert] = []
  @Published var selectedAlert: HomeAlert?

  func refreshAlerts(
    profiles: [BlockedProfiles],
    authorizationStatus: AuthorizationStatus
  ) {
    var updatedAlerts: [HomeAlert] = []

    if authorizationStatus != .approved {
      updatedAlerts.append(
        HomeAlert(
          type: .screenTimeAccess,
          title: String(localized: "Screen Time access needed"),
          message: String(localized: "Blocking is paused until access is restored."),
          detailMessage:
            String(
              localized:
                "Ctrus needs Screen Time access to block apps and websites. Grant access again to restore blocking."
            ),
          primaryActionTitle: String(localized: "Allow Screen Time Access"),
          iconName: "exclamationmark.shield.fill"
        ))
    }

    updatedAlerts.append(
      contentsOf:
        profiles
        .filter { $0.scheduleIsOutOfSync }
        .map { profile in
          HomeAlert(
            type: .scheduleOutOfSync(profileId: profile.id),
            title: String(localized: "Schedule needs repair"),
            message: String(localized: "\(profile.name)'s schedule is not running."),
            detailMessage:
              String(
                localized:
                  "\(profile.name)'s schedule is saved, but iOS is no longer monitoring it. This usually can happen when you combine Ctrus with other blocking apps, recommended to turn those apps off."
              ),
            primaryActionTitle: String(localized: "Fix Schedule"),
            iconName: "calendar.badge.exclamationmark"
          )
        }
    )

    alerts = updatedAlerts
    clearSelectedAlertIfResolved()
  }

  func present(_ alert: HomeAlert) {
    selectedAlert = alert
  }

  // Presents the "Screen Time access needed" alert if it's currently active.
  // Returns whether it was presented, so callers can bail out of whatever
  // action (e.g. starting a profile) required that access.
  @discardableResult
  func presentScreenTimeAccessAlertIfNeeded() -> Bool {
    guard let alert = alerts.first(where: { $0.type == .screenTimeAccess }) else {
      return false
    }
    present(alert)
    return true
  }

  func disabledReason(
    for alert: HomeAlert,
    profiles: [BlockedProfiles],
    isBlocking: Bool
  ) -> String? {
    switch alert.type {
    case .screenTimeAccess:
      return nil
    case .scheduleOutOfSync(let profileId):
      if profile(with: profileId, in: profiles) == nil {
        return String(localized: "The affected profile could not be found.")
      }

      if isBlocking {
        return String(localized: "Stop the active profile before repairing this schedule.")
      }

      return nil
    }
  }

  func canRunPrimaryAction(
    for alert: HomeAlert,
    profiles: [BlockedProfiles],
    isBlocking: Bool
  ) -> Bool {
    return disabledReason(for: alert, profiles: profiles, isBlocking: isBlocking) == nil
  }

  func runPrimaryAction(
    for alert: HomeAlert,
    profiles: [BlockedProfiles],
    isBlocking: Bool,
    requestAuthorizer: RequestAuthorizer,
    onScheduleRepaired: () -> Void
  ) {
    guard canRunPrimaryAction(for: alert, profiles: profiles, isBlocking: isBlocking) else {
      return
    }

    switch alert.type {
    case .screenTimeAccess:
      requestAuthorizer.requestAuthorization()
    case .scheduleOutOfSync(let profileId):
      guard let profile = profile(with: profileId, in: profiles) else { return }
      DeviceActivityCenterUtil.scheduleTimerActivity(for: profile)
      onScheduleRepaired()
    }
  }

  private func clearSelectedAlertIfResolved() {
    guard let selectedAlert else { return }
    if !alerts.contains(where: { $0.id == selectedAlert.id }) {
      self.selectedAlert = nil
    }
  }

  private func profile(with id: UUID, in profiles: [BlockedProfiles]) -> BlockedProfiles? {
    return profiles.first { $0.id == id }
  }
}
