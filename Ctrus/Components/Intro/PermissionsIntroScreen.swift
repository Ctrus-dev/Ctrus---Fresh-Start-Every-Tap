import SwiftUI

struct PermissionsIntroScreen: View {
  @EnvironmentObject private var themeManager: ThemeManager

  let showPasscodeMessage: Bool
  let onRequestAuthorization: () -> Void

  @State private var showContent: Bool = false

  var body: some View {
    // Matches HomeView's own outer spacing (30pt between the alerts row,
    // the model, and the Welcome block) so the model and button land in
    // exactly the same spot as the empty Home screen.
    VStack(spacing: 30) {
      // HomeView's alerts row sits above the model with 16pt of top padding,
      // then the VStack's own 30pt spacing to the model — it renders as
      // zero-height when there are no alerts (the common case here), so its
      // only visible effect is that 16+30 offset. Since the model is the
      // *first* child here, the VStack's spacing never applies before it,
      // so both numbers have to be folded into this one padding value.
      RotatingModel3DView(themeColor: themeManager.themeColor)
        .padding(.top, 46)
        .opacity(showContent ? 1 : 0)

      // Passcode warning: disabled, it was cutting into the access button
      // on small screens. The logic stays in AnimatedIntroContainer in case
      // it comes back in a less cramped layout.
      IntroCard(
        title: String(localized: "Welcome to Ctrus"),
        subtitle: String(localized: "We need Screen Time Access to get started"),
        iconName: "hourglass",
        action: onRequestAuthorization
      )
      .accessibilityLabel(String(localized: "Allow Screen Time Access"))
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 16)
      .padding(.vertical, 22)
      .opacity(showContent ? 1 : 0)
      .offset(y: showContent ? 0 : 20)

      Spacer()
    }
    // Devices with a physical Home button (no bottom safe-area inset, e.g.
    // iPhone SE) would otherwise sit flush against the screen edge here.
    .padding(.bottom, RotatingModel3DView.isCompactScreen ? 20 : 0)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(themeManager.pastelBackground.ignoresSafeArea())
    .onAppear {
      withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
        showContent = true
      }
    }
  }
}

#Preview {
  PermissionsIntroScreen(showPasscodeMessage: false, onRequestAuthorization: {})
    .environmentObject(ThemeManager.shared)
}
