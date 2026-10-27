import SwiftUI

struct Welcome: View {
  @EnvironmentObject var themeManager: ThemeManager
  let onGuidedTap: () -> Void

  var body: some View {
    IntroCard(
      title: String(localized: "First Steps"),
      subtitle: String(localized: "Let's get you started by creating your first profile"),
      iconName: "person.crop.circle",
      action: onGuidedTap
    )
    .accessibilityLabel(String(localized: "Start guided profile setup"))
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
