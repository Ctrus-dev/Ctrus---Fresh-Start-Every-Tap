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

        // Coming back to pick normal mode after access was already granted:
        // there's nothing left to set up.
        if mode == .normal && requestAuthorizer.isAuthorized {
          onFinished()
        }
      }
    } else if pendingChildModeSetup && requestAuthorizer.isAuthorized {
      ChildModeSetupView(
        onCancel: backToModeChoice,
        onFinished: {
          pendingChildModeSetup = false
          onFinished()
        }
      )
    } else {
      AnimatedIntroContainer(
        onRequestAuthorization: onRequestAuthorization
      )
      // Swiping in from the left edge goes back, like a navigation stack.
      .gesture(
        DragGesture(minimumDistance: 20)
          .onEnded { value in
            if value.startLocation.x < 40 && value.translation.width > 80 {
              backToModeChoice()
            }
          }
      )
      .accessibilityAction(.escape, backToModeChoice)
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
