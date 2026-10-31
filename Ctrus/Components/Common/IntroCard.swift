import SwiftUI

/// A tappable card with an icon, title and subtitle, drawn like the profile
/// cards on the home screen. Used on the first-launch and First Steps screens.
struct IntroCard: View {
  @EnvironmentObject private var themeManager: ThemeManager

  let title: String
  let subtitle: String
  let iconName: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 14) {
        Image(systemName: iconName)
          .font(.title3)
          .foregroundStyle(themeManager.themeColor)
          .frame(width: 32)

        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.headline)
            .foregroundColor(.fixedLightPrimaryText)

          Text(subtitle)
            .font(.subheadline)
            .foregroundColor(.fixedLightSecondaryText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer()

        Image(systemName: "chevron.right")
          .foregroundColor(.fixedLightSecondaryText)
      }
      .padding(16)
      .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          // Same border as the profile cards on the home screen.
          .strokeBorder(themeManager.themeColor, lineWidth: 3.5)
      )
    }
    .buttonStyle(.plain)
  }
}

#Preview {
  IntroCard(
    title: "Welcome to Ctrus",
    subtitle: "We need Screen Time Access to get started.",
    iconName: "hourglass",
    action: {}
  )
  .padding()
  .environmentObject(ThemeManager.shared)
}
