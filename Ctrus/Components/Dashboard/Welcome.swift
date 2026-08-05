import SwiftUI

struct Welcome: View {
  @EnvironmentObject var themeManager: ThemeManager
  let onGuidedTap: () -> Void

  var body: some View {
    VStack(spacing: 14) {
      Text("Getting Started")
        .font(.title)
        .fontWeight(.bold)
        .foregroundColor(.fixedLightPrimaryText)

      Text(
        "Let's get you started by creating your first profile. You can customize it as much or as little as you'd like."
      )
      .font(.subheadline)
      .foregroundColor(.fixedLightSecondaryText)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 8)

      ShimmerLauncherButton(
        title: "Create Profile",
        iconName: "person.crop.circle",
        height: 56,
        accessibilityLabel: "Start guided profile setup",
        action: onGuidedTap
      )
      .padding(.top, 6)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 22)
  }
}

#Preview {
  ZStack {
    Color.gray.opacity(0.1).ignoresSafeArea()

    Welcome(
      onGuidedTap: { print("Guided tapped") }
    )
    .padding(.horizontal)
    .environmentObject(ThemeManager.shared)
  }
}
