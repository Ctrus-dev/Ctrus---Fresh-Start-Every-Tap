import SwiftUI

struct AnimatedIntroContainer: View {
  @State private var showPasscodeMessage: Bool = false
  @State private var authorizationRequested: Bool = false
  let onRequestAuthorization: () -> Void

  private let passcodeMessageDelay: TimeInterval = 3.0

  var body: some View {
    PermissionsIntroScreen(
      showPasscodeMessage: showPasscodeMessage,
      onRequestAuthorization: handleRequestAuthorization
    )
  }

  private func handleRequestAuthorization() {
    authorizationRequested = true
    showPasscodeMessage = false
    onRequestAuthorization()

    // Show passcode message after delay if still on this screen
    DispatchQueue.main.asyncAfter(deadline: .now() + passcodeMessageDelay) {
      if authorizationRequested {
        withAnimation {
          showPasscodeMessage = true
        }
      }
    }
  }
}

#Preview {
  AnimatedIntroContainer(
    onRequestAuthorization: {
      print("Request authorization")
    }
  )
  .environmentObject(ThemeManager.shared)
}
