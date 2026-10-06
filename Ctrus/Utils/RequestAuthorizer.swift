import DeviceActivity
import FamilyControls
import ManagedSettings
import SwiftUI

class RequestAuthorizer: ObservableObject {
  @Published var isAuthorized = false

  func refreshAuthorizationStatus() {
    let isApproved = getAuthorizationStatus() == .approved
    SharedData.lastKnownAuthorizationApproved = isApproved

    Task { @MainActor in
      self.isAuthorized = isApproved
    }
  }

  func requestAuthorization() {
    Task {
      do {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        print("Individual authorization successful")

        SharedData.lastKnownAuthorizationApproved = true
        // Dispatch the update to the main thread
        await MainActor.run {
          self.isAuthorized = true
        }
      } catch {
        print("Error requesting authorization: \(error)")
        SharedData.lastKnownAuthorizationApproved = false
        await MainActor.run {
          self.isAuthorized = false
        }
      }
    }
  }

  func getAuthorizationStatus() -> AuthorizationStatus {
    return AuthorizationCenter.shared.authorizationStatus
  }
}
