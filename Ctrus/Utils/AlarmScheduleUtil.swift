import ActivityKit
import AlarmKit
import Foundation
import SwiftUI

/// The AlarmKit side of Alarm mode: sets and cancels the system alarms that
/// ring with the app closed, the phone locked, on silent or in a Focus.
@available(iOS 26.0, *)
enum AlarmScheduleUtil {
  /// When the alarm and its spares ring, from its own time: every minute for
  /// half an hour, so it comes back if it's silenced some other way than the
  /// Ctrus — slid away with the app then closed, the side button, or its
  /// notification swiped off. Not closer together: each spare takes over
  /// from one still ringing, so the alarm would keep restarting on screen.
  static let spareOffsets: [TimeInterval] = Array(stride(from: 0, through: 30 * 60, by: 60))

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
    installSoundsIfNeeded()

    var ids: [UUID] = []
    for offset in spareOffsets {
      let id = UUID()
      let fireDate = date.addingTimeInterval(offset)
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

  private static var hasInstalledSounds = false

  /// Copies the tones to Library/Sounds. Alert sounds are looked for there as
  /// well as in the app, and one that isn't found plays the system's sound
  /// instead without a word.
  private static func installSoundsIfNeeded() {
    guard !hasInstalledSounds else { return }
    hasInstalledSounds = true

    let fileManager = FileManager.default
    guard
      let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first,
      let bundled = Bundle.main.urls(forResourcesWithExtension: "caf", subdirectory: nil)
    else {
      return
    }

    let sounds = library.appendingPathComponent("Sounds", isDirectory: true)
    try? fileManager.createDirectory(at: sounds, withIntermediateDirectories: true)

    for source in bundled {
      let destination = sounds.appendingPathComponent(source.lastPathComponent)
      // Replaced every launch, so a tone changed in an update doesn't keep its old sound.
      try? fileManager.removeItem(at: destination)
      do {
        try fileManager.copyItem(at: source, to: destination)
      } catch {
        print("Alarm mode: couldn't copy \(source.lastPathComponent) to Library/Sounds: \(error)")
      }
    }
  }

  static var allAlarms: [Alarm] {
    (try? AlarmManager.shared.alarms) ?? []
  }

  static func cancel(_ ids: [UUID]) {
    for id in ids {
      // One that's ringing is stopped first, so it leaves the screen too.
      try? AlarmManager.shared.stop(id: id)
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
    // The same files the app plays while it's open, so the two sound alike.
    soundId == BlockedProfileSchedule.vibrateAlarmSound
      ? .named(WakeAlarmManager.silentSoundFile) : .named("\(soundId).caf")
  }
}
