import ActivityKit
import AlarmKit
import Foundation
import SwiftUI

/// The AlarmKit side of Alarm mode: sets and cancels the system alarms that
/// ring with the app closed, the phone locked, on silent or in a Focus.
@available(iOS 26.0, *)
enum AlarmScheduleUtil {
  /// The alarm, then this many spares a minute apart, so it keeps coming back
  /// if it's slid away and the app is closed without the Ctrus.
  static let alarmRepeatCount = 30
  static let alarmRepeatSeconds: TimeInterval = 60

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
    soundId: String
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
            at: fireDate, profileId: profileId, profileName: profileName, soundId: soundId)
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
    soundId: String
  ) -> AlarmManager.AlarmConfiguration<CtrusAlarmMetadata> {
    let title = LocalizedStringResource(stringLiteral: profileName)
    let alert: AlarmPresentation.Alert
    if #available(iOS 26.1, *) {
      alert = AlarmPresentation.Alert(title: title)
    } else {
      alert = AlarmPresentation.Alert(
        title: title,
        stopButton: AlarmButton(
          text: "Open Ctrus", textColor: .white, systemImageName: "lock.open")
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
