import ActivityKit
import AlarmKit
import Foundation
import SwiftUI

/// The AlarmKit side of Alarm mode: sets and cancels the system alarms that
/// ring with the app closed, the phone locked, on silent or in a Focus.
@available(iOS 26.0, *)
enum AlarmScheduleUtil {
  /// The alarm, then this many spares 15 seconds apart, so it keeps coming
  /// back for half an hour if it's silenced some other way than the Ctrus —
  /// slid away with the app then closed, the side button, or its
  /// notification swiped off.
  static let alarmRepeatCount = 120
  static let alarmRepeatSeconds: TimeInterval = 15

  static var isAuthorized: Bool {
    AlarmManager.shared.authorizationState == .authorized
  }

  static func requestAuthorization() async -> Bool {
    switch AlarmManager.shared.authorizationState {
    case .authorized:
      return true
    case .denied:
      return false
    case .notDetermined:
      return (try? await AlarmManager.shared.requestAuthorization()) == .authorized
    @unknown default:
      return false
    }
  }

  /// Sets the alarm at `date` plus its spares, and returns the ids it set.
  /// If AlarmKit refuses more, it keeps the ones it got.
  static func schedule(
    at date: Date,
    profileId: UUID,
    profileName: String,
    soundId: String,
    allowsSnooze: Bool
  ) async -> [UUID] {
    guard isAuthorized else { return [] }

    var ids: [UUID] = []
    for index in 0...alarmRepeatCount {
      let id = UUID()
      let fireDate = date.addingTimeInterval(Double(index) * alarmRepeatSeconds)
      do {
        _ = try await AlarmManager.shared.schedule(
          id: id,
          configuration: configuration(
            at: fireDate, profileId: profileId, profileName: profileName, soundId: soundId,
            allowsSnooze: allowsSnooze)
        )
        ids.append(id)
      } catch {
        print("Alarm mode: stopped setting alarms at \(ids.count): \(error)")
        break
      }
    }
    return ids
  }

  static func cancel(_ ids: [UUID]) {
    for id in ids {
      try? AlarmManager.shared.cancel(id: id)
    }
  }

  private static func configuration(
    at date: Date,
    profileId: UUID,
    profileName: String,
    soundId: String,
    allowsSnooze: Bool
  ) -> AlarmManager.AlarmConfiguration<CtrusAlarmMetadata> {
    let title = LocalizedStringResource(stringLiteral: profileName)
    // Custom rather than the system's own countdown, which would only hold
    // back this alarm and leave the spares a minute behind it ringing.
    let snoozeButton =
      allowsSnooze
      ? AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz") : nil
    let snoozeBehavior: AlarmPresentation.Alert.SecondaryButtonBehavior? =
      allowsSnooze ? .custom : nil

    let alert: AlarmPresentation.Alert
    if #available(iOS 26.1, *) {
      alert = AlarmPresentation.Alert(
        title: title,
        secondaryButton: snoozeButton,
        secondaryButtonBehavior: snoozeBehavior
      )
    } else {
      alert = AlarmPresentation.Alert(
        title: title,
        stopButton: AlarmButton(
          text: "Open Ctrus", textColor: .white, systemImageName: "lock.open"),
        secondaryButton: snoozeButton,
        secondaryButtonBehavior: snoozeBehavior
      )
    }

    let attributes = AlarmAttributes(
      presentation: AlarmPresentation(alert: alert),
      metadata: CtrusAlarmMetadata(profileId: profileId, profileName: profileName),
      tintColor: ThemeManager.shared.themeColor
    )

    return .alarm(
      schedule: .fixed(date),
      attributes: attributes,
      stopIntent: OpenAlarmProfileIntent(profileId: profileId.uuidString),
      secondaryIntent: allowsSnooze
        ? SnoozeAlarmProfileIntent(profileId: profileId.uuidString) : nil,
      sound: alertSound(for: soundId)
    )
  }

  private static func alertSound(for soundId: String) -> AlertConfiguration.AlertSound {
    switch soundId {
    case BlockedProfileSchedule.defaultAlarmSound:
      return .default
    case BlockedProfileSchedule.vibrateAlarmSound:
      return .named(WakeAlarmManager.silentSoundFile)
    default:
      return .named("\(soundId).caf")
    }
  }
}
