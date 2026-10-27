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
        Text("Welcome to Ctrus")
          .font(.title)
          .fontWeight(.bold)
          .foregroundColor(.fixedLightPrimaryText)

        modeButton(
          title: String(localized: "Normal mode"),
          subtitle: String(localized: "For your own phone."),
          iconName: "person.fill",
          mode: .normal
        )

        modeButton(
          title: String(localized: "Child mode"),
          subtitle: String(localized: "For your child's phone. Only you can end sessions."),
          iconName: "figure.and.child.holdinghands",
          mode: .child
        )
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

  private func modeButton(
    title: String,
    subtitle: String,
    iconName: String,
    mode: AppMode
  ) -> some View {
    Button {
      onChoose(mode)
    } label: {
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
          .strokeBorder(themeManager.themeColor, lineWidth: 2)
      )
    }
    .buttonStyle(.plain)
  }
}

#Preview {
  ModeChoiceIntroScreen(onChoose: { _ in })
    .environmentObject(ThemeManager.shared)
}
