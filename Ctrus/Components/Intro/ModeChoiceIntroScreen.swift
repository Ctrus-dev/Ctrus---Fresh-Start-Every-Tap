import SwiftUI

/// First screen on a new install: is this the person's own phone, or a
/// child's?
struct ModeChoiceIntroScreen: View {
  @EnvironmentObject private var themeManager: ThemeManager

  let onChoose: (AppMode) -> Void

  @State private var showContent = false

  var body: some View {
    VStack(spacing: 30) {
      RotatingModel3DView(themeColor: themeManager.themeColor)
        .padding(.top, 46)
        .opacity(showContent ? 1 : 0)

      VStack(spacing: 14) {
        IntroCard(
          title: String(localized: "Normal Mode"),
          subtitle: String(localized: "For your own phone."),
          iconName: "person.fill"
        ) {
          onChoose(.normal)
        }

        IntroCard(
          title: String(localized: "Child Mode"),
          subtitle: String(localized: "For your child's phone."),
          iconName: "figure.and.child.holdinghands"
        ) {
          onChoose(.child)
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 16)
      .padding(.vertical, 22)
      .opacity(showContent ? 1 : 0)
      .offset(y: showContent ? 0 : 20)

      Spacer()
    }
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
  ModeChoiceIntroScreen(onChoose: { _ in })
    .environmentObject(ThemeManager.shared)
}
