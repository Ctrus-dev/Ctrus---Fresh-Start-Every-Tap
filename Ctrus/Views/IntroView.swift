import SwiftUI

struct IntroView: View {
  @EnvironmentObject private var requestAuthorizer: RequestAuthorizer

  // Remembered so a child mode setup interrupted by closing the app picks up
  // where it left off instead of going back to the mode choice.
  @AppStorage("pendingChildModeSetup") private var pendingChildModeSetup = false
  @AppStorage("hasChosenAppMode") private var hasChosenAppMode = false

  let onRequestAuthorization: () -> Void
  let onFinished: () -> Void

  var body: some View {
    if !hasChosenAppMode {
      ModeChoiceIntroScreen { mode in
        pendingChildModeSetup = mode == .child
        hasChosenAppMode = true
      }
    } else if pendingChildModeSetup && requestAuthorizer.isAuthorized {
      ChildModeSetupView {
        pendingChildModeSetup = false
        onFinished()
      }
    } else {
      AnimatedIntroContainer(
        onRequestAuthorization: onRequestAuthorization
      )
    }
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
