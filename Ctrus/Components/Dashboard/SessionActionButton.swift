import SwiftUI
import UIKit

enum SessionActionRole {
  case standard
  case destructive
}

struct SessionActionButton: View {
  let title: String
  let iconName: String
  var imageName: String? = nil
  let role: SessionActionRole
  let themeColor: Color
  var requiresLongPress = false
  let action: () -> Void

  @State private var isPressed = false
  // Separate from `isPressed` so the border grow/shrink can use its own
  // (asymmetric) timing instead of the scale effect's spring.
  @State private var isHolding = false

  private let baseBorderWidth: CGFloat = 3.5
  private let heldBorderWidth: CGFloat = 5

  private var foregroundColor: Color {
    role == .destructive ? Color(hex: "FF3B30") : .black
  }

  private var borderColor: Color {
    role == .destructive ? Color(hex: "FF3B30") : themeColor
  }

  private var borderLineWidth: CGFloat {
    isHolding ? heldBorderWidth : baseBorderWidth
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
              withAnimation(pressing ? .linear(duration: 0.8) : .easeOut(duration: 0.2)) {
                isHolding = pressing
              }
            },
            perform: triggerAction
          )
      } else {
        Button(action: triggerAction) {
          label
        }
        .buttonStyle(SessionActionPressStyle())
      }
    }
  }

  private var label: some View {
    HStack(spacing: 8) {
      icon

      Text(title)
        .font(.system(size: 18, weight: .bold))
        .lineLimit(1)
        .minimumScaleFactor(0.82)
    }
    .offset(y: -1)
    .frame(maxWidth: .infinity)
    .frame(height: 56)
    .foregroundStyle(foregroundColor)
    // A wide, short bar like this reads as a pill in iOS system UI (e.g.
    // Control Center's Focus/volume pills) — a true `Capsule` (its default
    // `.circular` style) gives fully round semicircular ends. Forcing
    // `.continuous` style at this radius flattens those ends and reads as
    // rectangular instead.
    .background(Color.white, in: Capsule())
    .overlay(
      Capsule()
        .strokeBorder(borderColor, lineWidth: borderLineWidth)
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

struct SessionActionPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .animation(
        .spring(response: 0.24, dampingFraction: 0.74),
        value: configuration.isPressed
      )
  }
}

/// The "session is running" accessory shown next to a profile's summary row:
/// a live elapsed-time clock, a break countdown with a coffee icon, or a
/// "Paused" label — whichever applies. Sized to fill whatever fixed frame
/// the caller gives it (the profile balloon uses the usage chart's own
/// 118x62 slot), rather than to its own intrinsic content size.
struct SessionTimeAccessory: View {
  let displayTime: TimeInterval
  var isBreakActive = false
  var isPauseActive = false
  /// Overrides the inherited foreground color when set (e.g. the profile's
  /// theme color); leave `nil` to keep inheriting as before.
  var color: Color? = nil

  private let iconFont = Font.system(size: 16, weight: .semibold)
  // A large base size with a low minimum scale factor lets the clock text
  // grow to fill the given frame while still shrinking to fit longer
  // durations (hours-long sessions) without clipping.
  private let timeFont = Font.system(size: 28, weight: .bold, design: .monospaced)
  private let labelFont = Font.system(size: 17, weight: .semibold)

  private var stateTitle: String? {
    isPauseActive ? String(localized: "Paused") : nil
  }

  private var stateSystemImageName: String? {
    isPauseActive ? "pause.circle.fill" : nil
  }

  var body: some View {
    content
      .modifier(OptionalForegroundStyle(color: color))
  }

  @ViewBuilder
  private var content: some View {
    if let stateTitle {
      HStack(spacing: 4) {
        if let stateSystemImageName {
          Image(systemName: stateSystemImageName)
            .font(iconFont)
        }

        Text(stateTitle)
          .font(labelFont)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
      }
    } else if isBreakActive {
      HStack(spacing: 4) {
        Image(systemName: "cup.and.heat.waves.fill")
          .font(iconFont)

        Text(DateFormatters.formatDurationClock(displayTime))
          .font(timeFont)
          .lineLimit(1)
          .minimumScaleFactor(0.4)
          .contentTransition(.numericText())
          .animation(.default, value: displayTime)
      }
      .accessibilityLabel(String(localized: "On a Break"))
    } else {
      HStack(spacing: 4) {
        Image(systemName: "clock.fill")
          .font(iconFont)

        Text(DateFormatters.formatDurationClock(displayTime))
          .font(timeFont)
          .lineLimit(1)
          .minimumScaleFactor(0.4)
          .contentTransition(.numericText())
          .animation(.default, value: displayTime)
      }
    }
  }
}

/// Alarm mode's take on `SessionTimeAccessory`: counts down to the alarm,
/// says it's ringing once it's due, and counts a snooze down in its place.
/// During a break, the break's own countdown sits underneath.
struct AlarmSessionTimeAccessory: View {
  let alarmDate: Date?
  let snoozedUntil: Date?
  let isRinging: Bool
  /// Shown underneath while a break is on.
  let breakTime: TimeInterval?
  /// Stands in for the alarm countdown before its alarm has been set.
  let fallbackTime: TimeInterval
  let color: Color

  private let iconFont = Font.system(size: 16, weight: .semibold)
  private let labelFont = Font.system(size: 17, weight: .semibold)

  private var timeFont: Font {
    .system(size: breakTime == nil ? 28 : 22, weight: .bold, design: .monospaced)
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      VStack(spacing: 4) {
        topRow(now: context.date)

        if let breakTime {
          clockRow(
            systemImageName: "cup.and.heat.waves.fill",
            time: breakTime,
            font: .system(size: 17, weight: .bold, design: .monospaced)
          )
          .opacity(0.75)
          .accessibilityLabel(String(localized: "On a Break"))
        }
      }
    }
    .foregroundStyle(color)
  }

  @ViewBuilder
  private func topRow(now: Date) -> some View {
    if let snoozedUntil, snoozedUntil > now {
      clockRow(systemImageName: "zzz", time: snoozedUntil.timeIntervalSince(now), font: timeFont)
    } else if isRinging {
      HStack(spacing: 4) {
        Image(systemName: "alarm.waves.left.and.right.fill")
          .font(iconFont)
          .symbolEffect(.pulse, options: .repeating)

        Text("Ringing")
          .font(labelFont)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
      }
    } else {
      clockRow(
        systemImageName: "alarm.fill",
        time: alarmDate.map { $0.timeIntervalSince(now) } ?? fallbackTime,
        font: timeFont
      )
    }
  }

  private func clockRow(systemImageName: String, time: TimeInterval, font: Font) -> some View {
    HStack(spacing: 4) {
      Image(systemName: systemImageName)
        .font(iconFont)

      Text(DateFormatters.formatDurationClock(time))
        .font(font)
        .lineLimit(1)
        .minimumScaleFactor(0.4)
        .contentTransition(.numericText())
        .animation(.default, value: Int(time))
    }
  }
}

private struct OptionalForegroundStyle: ViewModifier {
  let color: Color?

  func body(content: Content) -> some View {
    if let color {
      content.foregroundStyle(color)
    } else {
      content
    }
  }
}
