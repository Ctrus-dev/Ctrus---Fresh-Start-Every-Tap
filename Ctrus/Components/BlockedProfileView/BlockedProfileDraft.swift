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
  @Published var allowSkip: Bool
  @Published var enableSnooze: Bool
  @Published var isOneTimeAlarm: Bool
  // Captured once at load so save() can tell whether the schedule itself
  // changed, instead of always bumping `updatedAt` on every save (which
  // re-arms the "too new, skip today" guard and can silently cancel that
  // day's automatic start just from an unrelated edit).
  private let initialSchedule: BlockedProfileSchedule
  @Published var selectedActivity: FamilyActivitySelection
  @Published var selectedStrategy: BlockingStrategy? {
    didSet {
      enforceStrategyBreaksPolicy()

      // Leaving Schedule for another mode drops the old schedule instead of
      // leaving it silently active in the background.
      if !useSchedule {
        schedule.days = []
      }

      // Alarm mode never ends on a timer; the alarm does that.
      if useAlarm {
        schedule.durationInHours = nil
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
    // Resolved locally, then used for both `schedule` and `initialSchedule`
    // below — reading `self.schedule` back to fill `initialSchedule` isn't
    // allowed until every stored property (selectedStrategy included) has a
    // value, which is exactly the circular problem this avoids.
    let resolvedSchedule =
      profile?.schedule
      ?? BlockedProfileSchedule(
        days: [],
        startHour: 9,
        startMinute: 0,
        durationInHours: nil,
        updatedAt: Date()
      )
    schedule = resolvedSchedule
    initialSchedule = resolvedSchedule
    allowSkip = profile?.allowSkip ?? false
    enableSnooze = profile?.enableSnooze ?? true
    isOneTimeAlarm = profile?.isOneTimeAlarm ?? false

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

  /// Schedule and Alarm both start on their own and share the schedule step.
  var useSchedule: Bool {
    return StrategyManager.scheduledStrategyIds.contains(selectedStrategy?.getIdentifier() ?? "")
  }

  var useAlarm: Bool {
    return selectedStrategy?.getIdentifier() == AlarmBlockingStrategy.id
  }

  var useOneTimeAlarm: Bool {
    useAlarm && isOneTimeAlarm
  }

  var hasValidSchedule: Bool {
    (useOneTimeAlarm || !schedule.days.isEmpty) && (!useAlarm || schedule.hasValidAlarmTime)
  }

  func save(
    existingProfile: BlockedProfiles?,
    in context: ModelContext
  ) throws -> BlockedProfiles {
    // A one-time alarm runs on whichever day its start time comes next.
    if useOneTimeAlarm, let start = nextOneTimeStart(),
      let weekday = Weekday(rawValue: Calendar.current.component(.weekday, from: start))
    {
      schedule.days = [weekday]
      allowSkip = false
    }

    if schedule != initialSchedule {
      schedule.updatedAt = Date()
    }

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
        allowSkip: allowSkip,
        enableSnooze: enableSnooze,
        isOneTimeAlarm: useOneTimeAlarm,
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
      allowSkip: allowSkip,
      enableSnooze: enableSnooze,
      isOneTimeAlarm: useOneTimeAlarm,
      disableBackgroundStops: disableBackgroundStops,
      enableEmergencyUnblock: enableEmergencyUnblock
    )

    DeviceActivityCenterUtil.scheduleTimerActivity(for: newProfile)
    return newProfile
  }

  // Far enough ahead that saving now doesn't fall inside the settle window
  // the Screen Time extension ignores.
  private func nextOneTimeStart(now: Date = Date()) -> Date? {
    Calendar.current.nextDate(
      after: now.addingTimeInterval(BlockedProfileSchedule.registrationSettleSeconds),
      matching: DateComponents(hour: schedule.startHour, minute: schedule.startMinute, second: 0),
      matchingPolicy: .nextTime
    )
  }

  private func enforceStrategyBreaksPolicy() {
    if selectedStrategyAllowsTimedBreaks {
      return
    }

    enableBreaks = false
    allowMultipleBreaks = false
  }
}
