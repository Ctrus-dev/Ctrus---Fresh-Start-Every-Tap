import SwiftUI
import UIKit

/// Profile card: hold it to start the session, tap it while active to
/// reveal break/emergency/stop, tap again to collapse.
struct ProfileBalloonRow: View {
  @EnvironmentObject private var themeManager: ThemeManager

  let profile: BlockedProfiles
  let isBlocking: Bool
  let isActive: Bool
  let isAuthorized: Bool
  let elapsedTime: TimeInterval
  let displayTime: TimeInterval
  let isBreakActive: Bool
  let isBreakAvailable: Bool
  let isPauseActive: Bool
  let onStartTapped: () -> Void
  let onStopTapped: () -> Void
  let onBreakTapped: () -> Void
  let onEditTapped: () -> Void
  let onStatsTapped: () -> Void

  @State private var isExpanded = false
  @State private var isHolding = false
  // Separate from `isHolding` so the scale effect can use its own spring
  // instead of the border's (asymmetric) grow/shrink timing.
  @State private var isPressed = false
  @State private var showEmergencyView = false

  private let baseBorderWidth: CGFloat = 3.5
  private let heldBorderWidth: CGFloat = 5

  private var canStart: Bool {
    !isBlocking
  }

  private var showStopButton: Bool {
    profile.showStopButton(elapsedTime: elapsedTime)
  }

  private var blockingStrategy: BlockingStrategy? {
    guard let strategyId = profile.blockingStrategyId else { return nil }
    return StrategyManager.getStrategyFromId(id: strategyId)
  }

  private var stopButtonAction: BlockingStrategySessionAction {
    blockingStrategy?.activeSessionAction(isPauseActive: isPauseActive) ?? .stop()
  }

  private var breakButtonTitle: String {
    isBreakActive
      ? String(localized: "Hold to Stop Break")
      : String(localized: "Hold to Start Break")
  }

  private var borderWidth: CGFloat {
    // The grown border is only meaningful while holding to start — once the
    // session is active there's nothing to confirm, so always show the
    // plain border regardless of any in-flight press state.
    guard !isActive, isHolding else { return baseBorderWidth }
    return heldBorderWidth
  }

  var body: some View {
    VStack(spacing: 0) {
      if isActive {
        activeHeader

        if isExpanded {
          expandedActions
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .padding(.top, 4)
            // Plain opacity only: a `.move` transition here slid the
            // buttons upward over the header while fading instead of
            // shrinking away in place.
            .transition(.opacity)
        }
      } else {
        inactiveRow
      }
    }
    .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .strokeBorder(themeManager.themeColor, lineWidth: borderWidth)
    )
    // Without this, the card's height collapses to its new (shorter) size
    // immediately while the departing buttons keep fading out at their old,
    // now out-of-bounds position — they end up floating, semi-transparent,
    // below an already-closed card instead of shrinking away inside it.
    .clipped()
    .scaleEffect(isPressed ? 0.97 : 1)
    .animation(.spring(response: 0.24, dampingFraction: 0.74), value: isPressed)
    .onChange(of: isActive) { _, newValue in
      // A press that starts the session can end (finger lifts) after the
      // view has already swapped to `activeHeader`, which unmounts the
      // gesture that would normally reset `isHolding`/`isPressed` — leaving
      // the border/scale stuck until cleared here explicitly.
      isHolding = false
      isPressed = false
      if !newValue {
        isExpanded = false
      }
    }
    .sheet(isPresented: $showEmergencyView) {
      EmergencyView()
        .presentationDetents(
          RotatingModel3DView.isCompactScreen ? [.height(480), .large] : [.height(350), .large]
        )
        .preferredColorScheme(.dark)
    }
  }

  // MARK: - Inactive

  private var inactiveRow: some View {
    HStack(spacing: 12) {
      // No tap target here — the name/metadata area is part of the
      // press-and-hold-to-start zone; editing is still reachable from the
      // "…" menu.
      ProfileSummaryContent(
        profile: profile,
        isActive: false,
        metadata: .appsAndDomains,
        showsStatusLine: true,
        layout: .dashboard,
        statusMode: .scheduleOnly,
        forcedLight: true
      )
      .frame(maxWidth: .infinity, alignment: .leading)

      Button(action: onStatsTapped) {
        ProfileUsageMiniBarChart(profile: profile, forcedLight: true)
          .frame(width: 118, height: 62)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Show \(profile.name) insights")

      inactiveMenu
    }
    .padding(16)
    .contentShape(Rectangle())
    // `.simultaneousGesture` so the Edit/Insights/menu buttons above keep
    // receiving their own taps — only a sustained press anywhere on the
    // card counts toward starting the profile.
    .simultaneousGesture(
      DragGesture(minimumDistance: 0)
        .onChanged { _ in
          guard canStart, !isHolding else { return }
          isPressed = true
          withAnimation(.linear(duration: 0.8)) {
            isHolding = true
          }
        }
        .onEnded { _ in
          isPressed = false
          withAnimation(.easeOut(duration: 0.2)) {
            isHolding = false
          }
        }
    )
    .simultaneousGesture(
      LongPressGesture(minimumDuration: 0.8)
        .onEnded { _ in
          // The hold itself is done the moment this fires — reset right
          // here rather than relying solely on the drag gesture's `onEnded`
          // (finger lifting), which can be interrupted before it runs if
          // `onStartTapped` triggers a popup (e.g. the Screen Time access
          // alert), leaving the border stuck grown after dismissing it.
          isPressed = false
          withAnimation(.easeOut(duration: 0.2)) {
            isHolding = false
          }
          guard canStart else { return }
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
          onStartTapped()
        }
    )
  }

  private var inactiveMenu: some View {
    Menu {
      Button(action: onStatsTapped) {
        Label("Insights", systemImage: "chart.line.uptrend.xyaxis")
      }

      Button(action: onEditTapped) {
        Label("Edit", systemImage: "pencil")
      }

      if isAuthorized {
        Button(action: onStartTapped) {
          Label("Start", systemImage: "play.fill")
        }
        .disabled(!canStart)
      }
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.gray)
        .frame(width: 32, height: 44)
        .contentShape(Rectangle())
    }
    .accessibilityLabel("More actions for \(profile.name)")
  }

  // MARK: - Active

  private var activeHeader: some View {
    HStack(spacing: 12) {
      Button(action: toggleExpanded) {
        ProfileSummaryContent(
          profile: profile,
          isActive: false,
          metadata: .appsAndDomains,
          showsStatusLine: true,
          layout: .dashboard,
          statusMode: .scheduleOnly,
          forcedLight: true
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(activeAccessibilityLabel)

      // Same fixed 118x62 slot, in the same place in the row, that the
      // usage chart occupies when inactive — keeps the card's size and
      // layout identical between the two states.
      Button(action: toggleExpanded) {
        SessionTimeAccessory(
          displayTime: displayTime,
          isBreakActive: isBreakActive,
          isPauseActive: isPauseActive,
          color: themeManager.themeColor
        )
        .frame(width: 118, height: 62)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      activeMenu
    }
    .padding(16)
  }

  private var activeMenu: some View {
    Menu {
      Button(action: onStatsTapped) {
        Label("Insights", systemImage: "chart.line.uptrend.xyaxis")
      }

      Button(action: onEditTapped) {
        Label("Edit", systemImage: "pencil")
      }

      Button(action: stopTapped) {
        Label(stopButtonAction.title, systemImage: stopButtonAction.systemImageName)
      }
      .disabled(!showStopButton)
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.gray)
        .frame(width: 32, height: 44)
        .contentShape(Rectangle())
    }
    .accessibilityLabel("More actions for \(profile.name)")
  }

  private var activeAccessibilityLabel: String {
    if isPauseActive {
      return String(localized: "Paused Profile \(profile.name)")
    }
    return String(localized: "Active Profile \(profile.name)")
  }

  private var expandedActions: some View {
    VStack(spacing: 12) {
      if !isPauseActive && isBreakAvailable {
        SessionActionButton(
          title: breakButtonTitle,
          iconName: "cup.and.heat.waves.fill",
          role: .standard,
          themeColor: themeManager.themeColor,
          requiresLongPress: true,
          action: onBreakTapped
        )
      }

      HStack(spacing: 12) {
        if profile.enableEmergencyUnblock {
          SessionActionButton(
            title: String(localized: "Emergency"),
            iconName: "exclamationmark.triangle.fill",
            role: .destructive,
            themeColor: themeManager.themeColor,
            action: {
              showEmergencyView = true
            }
          )
        }

        if showStopButton {
          SessionActionButton(
            title: stopButtonAction.title,
            iconName: stopButtonAction.systemImageName,
            imageName: stopButtonAction.assetImageName,
            role: .standard,
            themeColor: themeManager.themeColor,
            action: stopTapped
          )
        }
      }
    }
  }

  private func toggleExpanded() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    withAnimation(.easeInOut(duration: 0.3)) {
      isExpanded.toggle()
    }
  }

  private func stopTapped() {
    // Collapse immediately instead of waiting on `isActive` to flip back —
    // ending the session takes a moment, and until it does the buttons
    // (borders included) were still fully visible after tapping Stop.
    withAnimation(.easeInOut(duration: 0.25)) {
      isExpanded = false
    }
    onStopTapped()
  }
}
