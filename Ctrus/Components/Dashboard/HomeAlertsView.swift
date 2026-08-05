import SwiftUI

struct HomeAlertsView: View {
  let alerts: [HomeAlert]
  let onAlertTapped: (HomeAlert) -> Void

  var body: some View {
    if !alerts.isEmpty {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(alerts) { alert in
            Button {
              onAlertTapped(alert)
            } label: {
              HomeAlertCard(alert: alert)
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }
}

private struct HomeAlertCard: View {
  let alert: HomeAlert

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: alert.iconName)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)

      Text(alert.title)
        .font(.footnote)
        .fontWeight(.semibold)
        .foregroundStyle(.white)
        .lineLimit(1)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .background(
      Color.red.opacity(0.85),
      in: Capsule()
    )
    .accessibilityLabel(alert.title)
    .accessibilityHint(alert.message)
  }
}

struct HomeAlertDetailView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject var themeManager: ThemeManager

  let alert: HomeAlert
  let disabledReason: String?
  let onPrimaryAction: () -> Void

  private var canRunPrimaryAction: Bool { disabledReason == nil }

  var body: some View {
    NavigationStack {
      VStack(spacing: 22) {
        Spacer(minLength: 10)

        Image(systemName: alert.iconName)
          .font(.system(size: 50, weight: .semibold))
          .foregroundStyle(.red)
          .frame(width: 104, height: 104)

        VStack(spacing: 10) {
          Text(alert.title)
            .font(.title2.weight(.bold))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)

          Text(alert.detailMessage)
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 28)

        if let disabledReason {
          Text(disabledReason)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              Color(.secondarySystemBackground),
              in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }

        Spacer(minLength: 12)

        ActionButton(
          title: alert.primaryActionTitle,
          backgroundColor: themeManager.themeColor,
          isDisabled: !canRunPrimaryAction,
          action: runPrimaryAction
        )
      }
      .padding()
      .navigationTitle("Details")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .accessibilityLabel("Cancel")
        }
      }
    }
  }

  private func runPrimaryAction() {
    onPrimaryAction()
    dismiss()
  }
}

#Preview {
  HomeAlertsView(
    alerts: [
      HomeAlert(
        type: .screenTimeAccess,
        title: "Screen Time access needed",
        message: "Blocking is paused until access is restored.",
        detailMessage:
          "Ctrus needs Screen Time access to block apps and websites. Grant access again to restore blocking.",
        primaryActionTitle: "Allow Screen Time Access",
        iconName: "exclamationmark.shield.fill"
      )
    ],
    onAlertTapped: { _ in }
  )
  .padding()
  .environmentObject(ThemeManager.shared)
}
