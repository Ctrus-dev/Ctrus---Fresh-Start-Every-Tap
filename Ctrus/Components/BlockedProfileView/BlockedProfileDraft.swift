import Combine
import FamilyControls
import Foundation
import SwiftData
import SwiftUI

final class BlockedProfileDraft: ObservableObject {
  private(set) var isDirty = false
  private var dirtyTrackingCancellable: AnyCancellable?

  @Published var name: String
  @Published var enableLiveActivity: Bool
  @Published var enableReminder: Bool
  @Published var enableBreaks: Bool
  @Published var breakTimeInMinutes: Int
  @Published var allowMultipleBreaks: Bool
  @Published var enableStrictMode: Bool
  @Published var enableBlockAppInstallation: Bool
  @Published var reminderTimeInMinutes: Int
  @Published var customReminderMessage: String
  @Published var enableAllowMode: Bool
  @Published var enableAllowModeDomain: Bool
  @Published var enableSafariBlocking: Bool
  @Published var enableAdultContentBlocking: Bool
  @Published var disableBackgroundStops: Bool
  @Published var enableEmergencyUnblock: Bool
  @Published var domains: [String]
  @Published var physicalUnblockItems: [PhysicalUnblockItem]
  @Published var schedule: BlockedProfileSchedule
  @Published var selectedActivity: FamilyActivitySelection
  @Published var selectedStrategy: BlockingStrategy? {
    didSet {
      enforceStrategyBreaksPolicy()

      if useSchedule {
        // The schedule only drives the automatic start; stopping always
        // requires the Ctrus NFC, so there is no user-facing end time.
        // DeviceActivityCenter still needs an interval end, so this just
        // keeps the monitored window open for the rest of the day.
        schedule.endHour = 23
        schedule.endMinute = 59
      } else {
        // Leaving Schedule for another mode drops the old schedule instead
        // of leaving it silently active in the background.
        schedule.days = []
      }
    }
  }

  init(profile: BlockedProfiles? = nil) {
    name = profile?.name ?? ""
    selectedActivity = profile?.selectedActivity ?? FamilyActivitySelection()
    enableLiveActivity = profile?.enableLiveActivity ?? false
    enableBreaks = profile?.enableBreaks ?? false
    breakTimeInMinutes = profile?.breakTimeInMinutes ?? 10
    allowMultipleBreaks = profile?.allowMultipleBreaks ?? false
    enableStrictMode = profile?.enableStrictMode ?? true
    enableBlockAppInstallation = profile?.enableBlockAppInstallation ?? false
    enableAllowMode = profile?.enableAllowMode ?? false
    enableAllowModeDomain = profile?.enableAllowModeDomains ?? false
    enableSafariBlocking = profile?.enableSafariBlocking ?? true
    enableAdultContentBlocking = profile?.enableAdultContentBlocking ?? false
    enableReminder = profile?.reminderTimeInSeconds != nil
    disableBackgroundStops = profile?.disableBackgroundStops ?? true
    enableEmergencyUnblock = profile?.enableEmergencyUnblock ?? true
    reminderTimeInMinutes = Int(profile?.reminderTimeInSeconds ?? 900) / 60
    customReminderMessage = profile?.customReminderMessage ?? ""
    domains = profile?.domains ?? []
    physicalUnblockItems = profile?.physicalUnblockItems ?? []
    schedule =
      profile?.schedule
      ?? BlockedProfileSchedule(
        days: [],
        startHour: 9,
        startMinute: 0,
        endHour: 17,
        endMinute: 0,
        updatedAt: Date()
      )

    if let profileStrategyId = profile?.blockingStrategyId {
      selectedStrategy = StrategyManager.getStrategyFromId(id: profileStrategyId)
    } else {
      selectedStrategy = NFCBlockingStrategy()
    }

    enforceStrategyBreaksPolicy()

    // Track edits made after initial setup so we can warn before discarding them.
    dirtyTrackingCancellable = objectWillChange.sink { [weak self] _ in
      self?.isDirty = true
    }
  }

  var isValid: Bool {
    return !name.isEmpty
  }

  var selectedStrategyAllowsTimedBreaks: Bool {
    return selectedStrategy?.allowsTimedBreaks ?? true
  }

  var useSchedule: Bool {
    return selectedStrategy?.getIdentifier() == ScheduleBlockingStrategy.id
  }

  func save(
    existingProfile: BlockedProfiles?,
    in context: ModelContext
  ) throws -> BlockedProfiles {
    schedule.updatedAt = Date()

    let reminderTimeSeconds: UInt32? =
      enableReminder ? UInt32(reminderTimeInMinutes * 60) : nil
    let physicalUnblockItemsToSave: [PhysicalUnblockItem]? =
      physicalUnblockItems.isEmpty ? nil : physicalUnblockItems
    let enableTimedBreaksToSave = selectedStrategyAllowsTimedBreaks && enableBreaks

    if let existingProfile {
      let updatedProfile = try BlockedProfiles.updateProfile(
        existingProfile,
        in: context,
        name: name,
        selection: selectedActivity,
        blockingStrategyId: selectedStrategy?.getIdentifier(),
        enableLiveActivity: enableLiveActivity,
        reminderTime: reminderTimeSeconds,
        customReminderMessage: customReminderMessage,
        enableBreaks: enableTimedBreaksToSave,
        breakTimeInMinutes: breakTimeInMinutes,
        allowMultipleBreaks: enableTimedBreaksToSave && allowMultipleBreaks,
        enableStrictMode: enableStrictMode,
        enableBlockAppInstallation: enableBlockAppInstallation,
        enableAllowMode: enableAllowMode,
        enableAllowModeDomains: enableAllowModeDomain,
        enableSafariBlocking: enableSafariBlocking,
        enableAdultContentBlocking: enableAdultContentBlocking,
        domains: domains,
        physicalUnblockItems: .some(physicalUnblockItemsToSave),
        schedule: schedule,
        disableBackgroundStops: disableBackgroundStops,
        enableEmergencyUnblock: enableEmergencyUnblock
      )

      DeviceActivityCenterUtil.scheduleTimerActivity(for: updatedProfile)
      return updatedProfile
    }

    let newProfile = try BlockedProfiles.createProfile(
      in: context,
      name: name,
      selection: selectedActivity,
      blockingStrategyId: selectedStrategy?.getIdentifier() ?? NFCBlockingStrategy.id,
      enableLiveActivity: enableLiveActivity,
      reminderTimeInSeconds: reminderTimeSeconds,
      customReminderMessage: customReminderMessage,
      enableBreaks: enableTimedBreaksToSave,
      breakTimeInMinutes: breakTimeInMinutes,
      allowMultipleBreaks: enableTimedBreaksToSave && allowMultipleBreaks,
      enableStrictMode: enableStrictMode,
      enableBlockAppInstallation: enableBlockAppInstallation,
      enableAllowMode: enableAllowMode,
      enableAllowModeDomains: enableAllowModeDomain,
      enableSafariBlocking: enableSafariBlocking,
      enableAdultContentBlocking: enableAdultContentBlocking,
      domains: domains,
      physicalUnblockItems: physicalUnblockItemsToSave,
      schedule: schedule,
      disableBackgroundStops: disableBackgroundStops,
      enableEmergencyUnblock: enableEmergencyUnblock
    )

    DeviceActivityCenterUtil.scheduleTimerActivity(for: newProfile)
    return newProfile
  }

  private func enforceStrategyBreaksPolicy() {
    if selectedStrategyAllowsTimedBreaks {
      return
    }

    enableBreaks = false
    allowMultipleBreaks = false
  }
}
