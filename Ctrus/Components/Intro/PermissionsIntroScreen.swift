import SwiftUI

struct PermissionsIntroScreen: View {
  @EnvironmentObject private var themeManager: ThemeManager

  let showPasscodeMessage: Bool
  let onRequestAuthorization: () -> Void

  @State private var showContent: Bool = false

  var body: some View {
    VStack(spacing: 0) {
      // Header
      VStack(spacing: 8) {
        Text("Welcome to Ctrus")
          .font(.system(size: 34, weight: .bold))
          .foregroundColor(.fixedLightPrimaryText)
          .opacity(showContent ? 1 : 0)
          .offset(y: showContent ? 0 : -20)

        Text("We need Screen Time Access to get started")
          .font(.system(size: 16))
          .foregroundColor(.fixedLightSecondaryText)
          .opacity(showContent ? 1 : 0)
          .offset(y: showContent ? 0 : -20)
      }

      Spacer()

      RotatingModel3DView(themeColor: themeManager.themeColor)
        .opacity(showContent ? 1 : 0)

      Spacer()

      // Message text
      VStack(spacing: 16) {
        (Text("Ctrus is 100% open source, ")
          + Text("read the code yourself")
          .foregroundColor(themeManager.themeColor)
          + Text(" if you're skeptical"))
          .font(.system(size: 16, weight: .medium))
          .foregroundColor(.fixedLightSecondaryText)
          .multilineTextAlignment(.center)
          .lineSpacing(4)
          .onTapGesture {
            if let url = URL(string: "https://github.com/Ctrus-dev/Ctrus---Fresh-Start-Every-Tap") {
              UIApplication.shared.open(url)
            }
          }

        // Passcode warning message
        if showPasscodeMessage {
          HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundColor(.orange)
            Text(
              "Still here? You need to set a passcode on your phone for Screen Time to work properly."
            )
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.orange)
            .multilineTextAlignment(.center)
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
          .background(
            RoundedRectangle(cornerRadius: 12)
              .fill(Color.orange.opacity(0.15))
          )
          .transition(.opacity.combined(with: .move(edge: .bottom)))
        }

        ShimmerLauncherButton(
          title: "Allow Screen Time Access",
          iconName: nil,
          height: 56,
          accessibilityLabel: "Allow Screen Time Access",
          action: onRequestAuthorization
        )
        .padding(.top, 6)
      }
      .padding(.horizontal, 10)
      .opacity(showContent ? 1 : 0)
      .offset(y: showContent ? 0 : 20)
    }
    .padding(.top, 10)
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
