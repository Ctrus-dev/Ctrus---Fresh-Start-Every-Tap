import Combine
import DeviceActivity
import FamilyControls
import ManagedSettings
import SwiftUI

class RequestAuthorizer: ObservableObject {
  @Published var isAuthorized = false

  // Right after a cold launch (e.g. the app was swiped away from the app
  // switcher), AuthorizationCenter reports .notDetermined for a moment before
  // it syncs with the system and flips to .approved. Taking that first read at
  // face value made child mode log "permissions turned off" on every cold
  // launch. So when access was approved last time and the read is
  // .notDetermined, wait for the status to settle before believing it.
  private static let settleDelay: TimeInterval = 3

  private var statusObserver: AnyCancellable?
  private var pendingSettleCheck: DispatchWorkItem?

  init() {
    statusObserver = AuthorizationCenter.shared.$authorizationStatus
      .receive(on: DispatchQueue.main)
      .sink { [weak self] status in
        guard status != .notDetermined else { return }
        self?.apply(status)
      }
  }

  // What the rest of the app should treat as the current status: the
  // last known one while a cold-launch .notDetermined read is still settling.
  var effectiveStatus: AuthorizationStatus {
    let status = getAuthorizationStatus()
    if status == .notDetermined && pendingSettleCheck != nil {
      return .approved
    }
    return status
  }

  func refreshAuthorizationStatus() {
    let status = getAuthorizationStatus()

    if status == .notDetermined && SharedData.lastKnownAuthorizationApproved {
      scheduleSettleCheck()
      Task { @MainActor in
        self.isAuthorized = true
      }
      return
    }

    apply(status)
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

  private func scheduleSettleCheck() {
    guard pendingSettleCheck == nil else { return }

    let check = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.pendingSettleCheck = nil
      self.apply(self.getAuthorizationStatus())
    }
    pendingSettleCheck = check
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: check)
  }

  private func apply(_ status: AuthorizationStatus) {
    let isApproved = status == .approved

    if isApproved {
      pendingSettleCheck?.cancel()
      pendingSettleCheck = nil
    }

    // Logged once, when it goes from approved to not — not on every launch
    // while it stays off.
    if SharedData.lastKnownAuthorizationApproved && !isApproved {
      ChildModeStore.logTamper(.permissionRevoked)
    }

    SharedData.lastKnownAuthorizationApproved = isApproved

    Task { @MainActor in
      self.isAuthorized = isApproved
    }
  }
}
