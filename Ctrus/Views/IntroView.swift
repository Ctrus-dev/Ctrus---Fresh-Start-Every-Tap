import SwiftUI

// First launch: Screen Time access, then the choice of mode, then — for
// child mode — its own setup.
struct IntroView: View {
  @EnvironmentObject private var requestAuthorizer: RequestAuthorizer

  // Remembered so a child mode setup interrupted by closing the app picks up
  // where it left off instead of going back to the mode choice.
  @AppStorage("pendingChildModeSetup") private var pendingChildModeSetup = false
  @AppStorage("hasChosenAppMode") private var hasChosenAppMode = false
  @AppStorage("canReturnToModeChoice") private var canReturnToModeChoice = false

  let onRequestAuthorization: () -> Void
  let onFinished: () -> Void

  var body: some View {
    if !requestAuthorizer.isAuthorized {
      AnimatedIntroContainer(
        onRequestAuthorization: onRequestAuthorization
      )
    } else if pendingChildModeSetup {
      ChildModeSetupView(
        onCancel: backToModeChoice,
        onFinished: {
          pendingChildModeSetup = false
          onFinished()
        }
      )
    } else {
      ModeChoiceIntroScreen { mode in
        hasChosenAppMode = true

        if mode == .child {
          pendingChildModeSetup = true
        } else {
          canReturnToModeChoice = true
          onFinished()
        }
      }
    }
  }

  // Picked the wrong mode: go back and choose again, dropping anything a
  // half-done child mode setup already saved.
  private func backToModeChoice() {
    if !ChildModeStore.isChildMode {
      ParentCredentials.clearAll()
    }
    pendingChildModeSetup = false
    hasChosenAppMode = false
  }
}

#Preview {
  IntroView(
    onRequestAuthorization: {
      print("Request authorization tapped")
    },
    onFinished: {}
  )
  .environmentObject(ThemeManager.shared)
  .environmentObject(RequestAuthorizer())
}
