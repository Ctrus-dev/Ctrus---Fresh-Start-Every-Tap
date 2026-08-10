import FamilyControls
import SwiftUI
import UIKit

struct ActiveProfileSessionView: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var strategyManager: StrategyManager
  @EnvironmentObject private var themeManager: ThemeManager

  let profile: BlockedProfiles
  let elapsedTime: TimeInterval
  let displayTime: TimeInterval
  let isBreakAvailable: Bool
  let isBreakActive: Bool
  let isPauseActive: Bool
  let onBreakTapped: () -> Void
  let onStopTapped: () -> Void

  @State private var showEmergencyView = false
  @State private var showProfileInsights = false
  @State private var showingAlert = false
  @State private var alertMessage = ""
  @State private var focusMessageIndex = Self.initialFocusMessageIndex()

  private let focusMessageTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

  private var showStopButton: Bool {
    profile.showStopButton(elapsedTime: elapsedTime)
  }

  private var stopButtonAction: BlockingStrategySessionAction {
    blockingStrategy?.activeSessionAction(isPauseActive: isPauseActive) ?? .stop()
  }

  private var breakButtonTitle: String {
    "Hold to " + (isBreakActive ? "Stop Break" : "Start Break")
  }

  private var focusMessage: String {
    guard FocusMessages.messages.indices.contains(focusMessageIndex) else {
      return FocusMessages.getRandomMessage()
    }
    return FocusMessages.messages[focusMessageIndex]
  }

  private var blockingStrategy: BlockingStrategy? {
    guard let strategyId = profile.blockingStrategyId else {
      return nil
    }
    return StrategyManager.getStrategyFromId(id: strategyId)
  }

  private var isSoftUnblockStrategy: Bool {
    guard let strategyId = profile.blockingStrategyId else { return false }
    return [
      NFCSoftUnblockBlockingStrategy.id
    ].contains(strategyId)
  }

  private var supportingTextColor: Color {
    colorScheme == .dark ? Color.white.opacity(0.78) : Color.black.opacity(0.66)
  }

  var body: some View {
    ZStack {
      background

      VStack(alignment: .leading, spacing: 0) {
        header

        ScrollView {
          timerSection
            .padding(.top, 60)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)

        actionSection
      }
      .padding(.horizontal, 24)
      .padding(.top, 18)
      .padding(.bottom, 20)
    }
    .sheet(isPresented: $showEmergencyView) {
      EmergencyView()
        .presentationDetents([.height(350), .large])
    }
    .sheet(isPresented: $showProfileInsights) {
      ProfileInsightsView(profile: profile)
    }
    .sheet(isPresented: $strategyManager.showCustomStrategyView) {
      BlockingStrategyActionView(
        customView: strategyManager.customStrategyView,
        presentationDetents: strategyManager.customStrategyViewPresentationDetents
      )
    }
    .onReceive(focusMessageTimer) { _ in
      rotateFocusMessage()
    }
    .onReceive(strategyManager.$errorMessage) { errorMessage in
      guard let message = errorMessage else { return }
      alertMessage = message
      showingAlert = true
    }
    .alert("Whoops", isPresented: $showingAlert) {
      Button("OK", role: .cancel) {
        dismissAlert()
      }
    } message: {
      Text(alertMessage)
    }
  }

  private var background: some View {
    ZStack {
      themeManager.themeColor
        .ignoresSafeArea()

      LinearGradient(
        colors: [
          Color(.systemBackground).opacity(0.02),
          Color(.systemBackground).opacity(0.34),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 8) {
        Text(profile.name)
          .font(.largeTitle)
          .fontWeight(.bold)
          .lineLimit(2)
          .minimumScaleFactor(0.72)

        if let statusMessage {
          HStack(spacing: 6) {
            if let statusSystemIconName {
              Image(systemName: statusSystemIconName)
                .font(.system(size: 15, weight: .semibold))
            }

            Text(statusMessage)
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(.secondary)
          }
        }
      }

      Spacer(minLength: 12)

      HStack(spacing: 10) {
        Button(action: { showProfileInsights = true }) {
          Image(systemName: "chart.line.uptrend.xyaxis")
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 42, height: 42)
            .background(.thinMaterial, in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(ActiveSessionPressStyle())
        .foregroundStyle(.primary)
        .accessibilityLabel("Insights")

        Button(action: { dismiss() }) {
          Image(systemName: "xmark")
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 42, height: 42)
            .background(.thinMaterial, in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(ActiveSessionPressStyle())
        .foregroundStyle(.primary)
        .accessibilityLabel("Close")
      }
    }
  }

  private var statusMessage: String? {
    if isPauseActive {
      return "Paused"
    }
    if isBreakActive {
      return "On a Break"
    }
    return nil
  }

  private var statusSystemIconName: String? {
    if isPauseActive {
      return "pause.circle.fill"
    }
    return nil
  }

  private var timerSection: some View {
    VStack(spacing: 14) {
      Text(DateFormatters.formatDurationClock(displayTime))
        .font(.system(size: 58, weight: .bold, design: .monospaced))
        .lineLimit(1)
        .minimumScaleFactor(0.55)
        .contentTransition(.numericText())
        .animation(.default, value: displayTime)

      Text(focusMessage)
        .font(.headline)
        .fontWeight(.bold)
        .foregroundStyle(supportingTextColor)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: 0.35), value: focusMessage)

      if isSoftUnblockStrategy {
        SoftUnblockActiveGrantsCard(profileId: profile.id)
          .padding(.top, 16)
      }
    }
    .padding(.horizontal, 12)
  }

  private var actionSection: some View {
    VStack(spacing: 12) {
      if !isPauseActive && isBreakAvailable {
        ActiveSessionActionButton(
          title: breakButtonTitle,
          iconName: "cup.and.heat.waves.fill",
          role: isBreakActive ? .warning : .standard,
          requiresLongPress: true,
          action: onBreakTapped
        )
      }

      HStack(spacing: 12) {
        if profile.enableEmergencyUnblock {
          ActiveSessionActionButton(
            title: "Emergency",
            iconName: "exclamationmark.triangle.fill",
            role: .destructive,
            action: {
              showEmergencyView = true
            }
          )
        }

        if showStopButton {
          ActiveSessionActionButton(
            title: stopButtonAction.title,
            iconName: stopButtonAction.systemImageName,
            imageName: stopButtonAction.assetImageName,
            role: .standard,
            action: onStopTapped
          )
        }
      }
    }
  }

  private func rotateFocusMessage() {
    guard !FocusMessages.messages.isEmpty else { return }
    withAnimation(.easeInOut(duration: 0.35)) {
      focusMessageIndex = (focusMessageIndex + 1) % FocusMessages.messages.count
    }
  }

  private func dismissAlert() {
    showingAlert = false
    strategyManager.errorMessage = nil
  }

  private static func initialFocusMessageIndex() -> Int {
    guard !FocusMessages.messages.isEmpty else { return 0 }
    return Int.random(in: 0..<FocusMessages.messages.count)
  }
}

private struct SoftUnblockActiveGrantsCard: View {
  private static let visibleGrantLimit = 3

  let profileId: UUID

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { timeline in
      let activeGrants = SoftUnblockGrantStore.activeGrants(
        for: profileId,
        at: timeline.date
      )
      .sorted { lhs, rhs in
        if lhs.expiresAt == rhs.expiresAt {
          return lhs.createdAt < rhs.createdAt
        }
        return lhs.expiresAt < rhs.expiresAt
      }
      let visibleGrants = Array(activeGrants.prefix(Self.visibleGrantLimit))
      let overflowCount = activeGrants.count - visibleGrants.count

      if !activeGrants.isEmpty {
        VStack(spacing: 0) {
          ForEach(Array(visibleGrants.enumerated()), id: \.element.id) { index, grant in
            if index > 0 {
              Divider()
                .opacity(0.45)
            }

            SoftUnblockActiveGrantRow(
              grant: grant,
              date: timeline.date
            )
          }

          if overflowCount > 0 {
            Divider()
              .opacity(0.45)

            Text("+\(overflowCount) more active")
              .font(.footnote)
              .fontWeight(.semibold)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.vertical, 10)
          }
        }
        .padding(16)
        .background(
          .thinMaterial,
          in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.25), value: activeGrants.map(\.id))
      }
    }
  }
}

private struct SoftUnblockActiveGrantRow: View {
  let grant: SoftUnblockGrant
  let date: Date

  private var remainingSeconds: Int {
    max(Int(ceil(grant.expiresAt.timeIntervalSince(date))), 0)
  }

  private var countdownText: String {
    String(
      format: "%02d:%02d",
      remainingSeconds / 60,
      remainingSeconds % 60
    )
  }

  private var accessibilityCountdownText: String {
    let minutes = remainingSeconds / 60
    let seconds = remainingSeconds % 60
    let minuteLabel = minutes == 1 ? "minute" : "minutes"
    let secondLabel = seconds == 1 ? "second" : "seconds"
    return "\(minutes) \(minuteLabel), \(seconds) \(secondLabel) remaining"
  }

  var body: some View {
    HStack(spacing: 12) {
      resourceLabel
        .font(.subheadline)
        .fontWeight(.semibold)
        .lineLimit(1)
        .minimumScaleFactor(0.8)

      Spacer(minLength: 8)

      Text(countdownText)
        .font(.system(.subheadline, design: .monospaced, weight: .bold))
        .contentTransition(.numericText(countsDown: true))
        .accessibilityLabel(accessibilityCountdownText)
    }
    .padding(.vertical, 10)
  }

  @ViewBuilder
  private var resourceLabel: some View {
    switch grant.resource {
    case .application(let token):
      Label(token)
    case .category(let token):
      Label(token)
    }
  }
}

private enum ActiveSessionActionRole {
  case standard
  case warning
  case destructive
}

private struct ActiveSessionActionButton: View {
  let title: String
  let iconName: String
  var imageName: String? = nil
  let role: ActiveSessionActionRole
  var requiresLongPress = false
  let action: () -> Void

  @State private var isPressed = false

  private var foregroundColor: Color {
    switch role {
    case .standard:
      return .primary
    case .warning:
      return .orange
    case .destructive:
      return .red
    }
  }

  var body: some View {
    Group {
      if requiresLongPress {
        label
          .scaleEffect(isPressed ? 0.97 : 1)
          .animation(.spring(response: 0.24, dampingFraction: 0.74), value: isPressed)
          .onLongPressGesture(
            minimumDuration: 0.8,
            pressing: { pressing in
              isPressed = pressing
            },
            perform: triggerAction
          )
      } else {
        Button(action: triggerAction) {
          label
        }
        .buttonStyle(ActiveSessionPressStyle())
      }
    }
  }

  private var label: some View {
    HStack(spacing: 8) {
      icon

      Text(title)
        .font(.headline)
        .fontWeight(.semibold)
        .lineLimit(1)
        .minimumScaleFactor(0.82)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 56)
    .foregroundStyle(foregroundColor)
    .background(.thinMaterial, in: Capsule())
    .overlay(
      Capsule()
        .strokeBorder(foregroundColor.opacity(0.22), lineWidth: 1)
    )
    .contentShape(Capsule())
  }

  @ViewBuilder
  private var icon: some View {
    if let imageName {
      Image(imageName)
        .resizable()
        .scaledToFit()
        .frame(width: 24, height: 24)
    } else {
      Image(systemName: iconName)
        .font(.system(size: 15, weight: .bold))
    }
  }

  private func triggerAction() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    action()
  }
}

private struct ActiveSessionPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .animation(
        .spring(response: 0.24, dampingFraction: 0.74),
        value: configuration.isPressed
      )
  }
}

#Preview {
  ActiveProfileSessionView(
    profile: BlockedProfiles(name: "Work Focus"),
    elapsedTime: 3665,
    displayTime: 3665,
    isBreakAvailable: true,
    isBreakActive: false,
    isPauseActive: false,
    onBreakTapped: {},
    onStopTapped: {}
  )
  .environmentObject(StrategyManager())
  .environmentObject(ThemeManager.shared)
}
