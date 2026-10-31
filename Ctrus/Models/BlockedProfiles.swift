import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import SwiftData

@Model
class BlockedProfiles {
  @Attribute(.unique) var id: UUID
  var name: String
  var selectedActivity: FamilyActivitySelection
  var createdAt: Date
  var updatedAt: Date
  var blockingStrategyId: String?
  var strategyData: Data?
  var order: Int = 0

  var enableLiveActivity: Bool = false
  var reminderTimeInSeconds: UInt32?
  var enableBreaks: Bool = false
  var breakTimeInMinutes: Int = 10
  var allowMultipleBreaks: Bool = false
  // Alarm mode's stand-in for breaks.
  var enableSnooze: Bool = true
  // Alarm mode: deleted once its one session is stopped.
  var isOneTimeAlarm: Bool = false
  var enableStrictMode: Bool = false
  var enableBlockAppInstallation: Bool = false
  var enableAllowMode: Bool = false
  var enableAllowModeDomains: Bool = false
  var enableSafariBlocking: Bool = true
  var enableAdultContentBlocking: Bool = false

  @available(
    *, deprecated, message: "Use physicalUnblockItems instead - supports multiple NFC tags"
  )
  var physicalUnblockNFCTagId: String?

  /// Array of physical unblock items (NFC tags) that can unblock this profile
  /// Supports multiple NFC tags per profile
  var physicalUnblockItems: [PhysicalUnblockItem]?

  var domains: [String]? = nil

  var schedule: BlockedProfileSchedule? = nil

  var allowSkip: Bool = false
  var skipNextOccurrence: Date? = nil
  var skipUntil: Date? = nil

  // Child mode only
  var childTag: ChildTag? = nil
  var childTagCanStop: Bool = false

  var disableBackgroundStops: Bool = false

  var enableEmergencyUnblock: Bool = true

  var customReminderMessage: String?

  @Relationship var sessions: [BlockedProfileSession] = []

  var activeScheduleTimerActivity: DeviceActivityName? {
    return DeviceActivityCenterUtil.getActiveScheduleTimerActivity(for: self)
  }

  var scheduleIsOutOfSync: Bool {
    return self.schedule?.isActive == true
      && DeviceActivityCenterUtil.getActiveScheduleTimerActivity(for: self) == nil
  }

  var scheduleSkip: ScheduleSkip {
    ScheduleSkip(skipNextOccurrence: skipNextOccurrence, skipUntil: skipUntil)
  }

  // Skipping needs a tag to authorize it, so a profile without one never
  // offers it. In child mode the parents authorize it instead.
  var canSkipSessions: Bool {
    guard allowSkip, schedule?.isActive == true else { return false }
    return ChildModeStore.isChildMode || hasPhysicalUnblockItem(ofType: .nfc)
  }

  // Child mode treats every profile as if background stops were off, so
  // shortcuts, the widget and the profile link can't end a session.
  var blocksBackgroundStops: Bool {
    disableBackgroundStops || ChildModeStore.isChildMode
  }

  /// Child mode: only a parents' Ctrus, or this profile's child's Ctrus when
  /// it's allowed to, can end a session — matched by UID, never by URL.
  func childModeAllowsEnding(withTagId tagId: String) -> Bool {
    if ChildModeStore.isParentTag(uid: tagId) {
      return true
    }

    guard childTagCanStop, let childTag else { return false }
    return ChildModeStore.normalizedUID(childTag.uid) == ChildModeStore.normalizedUID(tagId)
  }

  var allowsTimedBreaks: Bool {
    let strategyId = blockingStrategyId ?? NFCBlockingStrategy.id
    return StrategyManager.getStrategyFromId(id: strategyId).allowsTimedBreaks
  }

  // MARK: - Physical Unblock Helpers

  /// Checks if a specific NFC tag can unblock this profile
  /// - Parameters:
  ///   - codeValue: The NFC tag ID to check
  ///   - type: The type of code
  /// - Returns: True if the code is in the allowed list, false otherwise
  func canUnblock(withCode codeValue: String, type: PhysicalUnblockItem.PhysicalUnblockType) -> Bool
  {
    guard let items = physicalUnblockItems else { return false }
    let normalizedCodeValue = PhysicalUnblockItem.normalizedCodeValue(codeValue, type: type)

    return items.contains {
      let itemCodeValue = PhysicalUnblockItem.normalizedCodeValue($0.codeValue, type: $0.type)

      return $0.type == type
        && itemCodeValue == normalizedCodeValue
    }
  }

  func hasPhysicalUnblockItem(ofType type: PhysicalUnblockItem.PhysicalUnblockType) -> Bool {
    guard let items = physicalUnblockItems else { return false }
    return items.contains { $0.type == type }
  }

  init(
    id: UUID = UUID(),
    name: String,
    selectedActivity: FamilyActivitySelection = FamilyActivitySelection(),
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    blockingStrategyId: String = NFCBlockingStrategy.id,
    strategyData: Data? = nil,
    enableLiveActivity: Bool = false,
    reminderTimeInSeconds: UInt32? = nil,
    customReminderMessage: String? = nil,
    enableBreaks: Bool = false,
    breakTimeInMinutes: Int = 10,
    allowMultipleBreaks: Bool = false,
    enableStrictMode: Bool = false,
    enableBlockAppInstallation: Bool = false,
    enableAllowMode: Bool = false,
    enableAllowModeDomains: Bool = false,
    enableSafariBlocking: Bool = true,
    enableAdultContentBlocking: Bool = false,
    order: Int = 0,
    domains: [String]? = nil,
    physicalUnblockItems: [PhysicalUnblockItem]? = nil,
    schedule: BlockedProfileSchedule? = nil,
    disableBackgroundStops: Bool = false,
    enableEmergencyUnblock: Bool = true
  ) {
    self.id = id
    self.name = name
    self.selectedActivity = selectedActivity
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.blockingStrategyId = blockingStrategyId
    self.strategyData = strategyData
    self.order = order

    self.enableLiveActivity = enableLiveActivity
    self.reminderTimeInSeconds = reminderTimeInSeconds
    self.customReminderMessage = customReminderMessage
    self.enableLiveActivity = enableLiveActivity
    self.enableBreaks = enableBreaks
    self.breakTimeInMinutes = breakTimeInMinutes
    self.allowMultipleBreaks = allowMultipleBreaks
    self.enableStrictMode = enableStrictMode
    self.enableBlockAppInstallation = enableBlockAppInstallation
    self.enableAllowMode = enableAllowMode
    self.enableAllowModeDomains = enableAllowModeDomains
    self.enableSafariBlocking = enableSafariBlocking
    self.enableAdultContentBlocking = enableAdultContentBlocking
    self.domains = domains

    self.physicalUnblockItems = PhysicalUnblockItem.normalizedItems(physicalUnblockItems)
    self.schedule = schedule

    self.disableBackgroundStops = disableBackgroundStops
    self.enableEmergencyUnblock = enableEmergencyUnblock
  }

  func showStopButton(elapsedTime: TimeInterval) -> Bool {
    guard let strategyData = self.strategyData else { return true }
    let timerData = StrategyTimerData.toStrategyTimerData(from: strategyData)

    // If hideStopButton is false, always show the stop button
    if !timerData.hideStopButton {
      return true
    }

    let durationInSeconds = Double(timerData.durationInMinutes * 60)
    return elapsedTime >= durationInSeconds
  }

  static func fetchProfiles(in context: ModelContext) throws
    -> [BlockedProfiles]
  {
    let descriptor = FetchDescriptor<BlockedProfiles>(
      sortBy: [
        SortDescriptor(\.order, order: .forward), SortDescriptor(\.createdAt, order: .reverse),
      ]
    )
    return try context.fetch(descriptor)
  }

  static func findProfile(byID id: UUID, in context: ModelContext) throws
    -> BlockedProfiles?
  {
    let descriptor = FetchDescriptor<BlockedProfiles>(
      predicate: #Predicate { $0.id == id }
    )
    return try context.fetch(descriptor).first
  }

  static func fetchMostRecentlyUpdatedProfile(in context: ModelContext) throws
    -> BlockedProfiles?
  {
    let descriptor = FetchDescriptor<BlockedProfiles>(
      sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
    )
    return try context.fetch(descriptor).first
  }

  static func updateProfile(
    _ profile: BlockedProfiles,
    in context: ModelContext,
    name: String? = nil,
    selection: FamilyActivitySelection? = nil,
    blockingStrategyId: String? = nil,
    strategyData: Data? = nil,
    enableLiveActivity: Bool? = nil,
    reminderTime: UInt32? = nil,
    customReminderMessage: String? = nil,
    enableBreaks: Bool? = nil,
    breakTimeInMinutes: Int? = nil,
    allowMultipleBreaks: Bool? = nil,
    enableStrictMode: Bool? = nil,
    enableBlockAppInstallation: Bool? = nil,
    enableAllowMode: Bool? = nil,
    enableAllowModeDomains: Bool? = nil,
    enableSafariBlocking: Bool? = nil,
    enableAdultContentBlocking: Bool? = nil,
    order: Int? = nil,
    domains: [String]? = nil,
    physicalUnblockItems: [PhysicalUnblockItem]?? = nil,
    schedule: BlockedProfileSchedule? = nil,
    allowSkip: Bool? = nil,
    enableSnooze: Bool? = nil,
    isOneTimeAlarm: Bool? = nil,
    childTag: ChildTag?? = nil,
    childTagCanStop: Bool? = nil,
    disableBackgroundStops: Bool? = nil,
    enableEmergencyUnblock: Bool? = nil
  ) throws -> BlockedProfiles {
    if let newName = name {
      profile.name = newName
    }

    if let newSelection = selection {
      profile.selectedActivity = newSelection
    }

    if let newStrategyId = blockingStrategyId {
      let oldStrategyId = profile.blockingStrategyId
      let timerStrategyIds = [
        NFCTimerBlockingStrategy.id,
        ShortcutTimerBlockingStrategy.id,
      ]

      // Check if switching FROM timer TO non-timer strategy
      let wasTimer = oldStrategyId != nil && timerStrategyIds.contains(oldStrategyId!)
      let isTimer = timerStrategyIds.contains(newStrategyId)

      if wasTimer && !isTimer {
        profile.strategyData = nil
      }

      profile.blockingStrategyId = newStrategyId
    }

    if let newStrategyData = strategyData {
      profile.strategyData = newStrategyData
    }

    if let newEnableLiveActivity = enableLiveActivity {
      profile.enableLiveActivity = newEnableLiveActivity
    }

    if let newEnableBreaks = enableBreaks {
      profile.enableBreaks = newEnableBreaks
    }

    if let newBreakTimeInMinutes = breakTimeInMinutes {
      profile.breakTimeInMinutes = newBreakTimeInMinutes
    }

    if let newAllowMultipleBreaks = allowMultipleBreaks {
      profile.allowMultipleBreaks = newAllowMultipleBreaks
    }

    if let newEnableStrictMode = enableStrictMode {
      profile.enableStrictMode = newEnableStrictMode
    }

    if let newEnableBlockAppInstallation = enableBlockAppInstallation {
      profile.enableBlockAppInstallation = newEnableBlockAppInstallation
    }

    if let newEnableAllowMode = enableAllowMode {
      profile.enableAllowMode = newEnableAllowMode
    }

    if let newEnableAllowModeDomains = enableAllowModeDomains {
      profile.enableAllowModeDomains = newEnableAllowModeDomains
    }

    if let newEnableSafariBlocking = enableSafariBlocking {
      profile.enableSafariBlocking = newEnableSafariBlocking
    }

    if let newEnableAdultContentBlocking = enableAdultContentBlocking {
      profile.enableAdultContentBlocking = newEnableAdultContentBlocking
    }

    if let newOrder = order {
      profile.order = newOrder
    }

    if let newDomains = domains {
      profile.domains = newDomains
    }

    if let newSchedule = schedule {
      profile.schedule = newSchedule
    }

    if let newAllowSkip = allowSkip {
      profile.allowSkip = newAllowSkip

      if !newAllowSkip {
        profile.skipNextOccurrence = nil
        profile.skipUntil = nil
      }
    }

    if let newEnableSnooze = enableSnooze {
      profile.enableSnooze = newEnableSnooze
    }

    if let newIsOneTimeAlarm = isOneTimeAlarm {
      profile.isOneTimeAlarm = newIsOneTimeAlarm
    }

    if let childTag {
      profile.childTag = childTag
    }

    if let newChildTagCanStop = childTagCanStop {
      profile.childTagCanStop = newChildTagCanStop
    }

    if let newDisableBackgroundStops = disableBackgroundStops {
      profile.disableBackgroundStops = newDisableBackgroundStops
    }

    if let newEnableEmergencyUnblock = enableEmergencyUnblock {
      profile.enableEmergencyUnblock = newEnableEmergencyUnblock
    }

    if let physicalUnblockItems {
      profile.physicalUnblockItems = PhysicalUnblockItem.normalizedItems(physicalUnblockItems)
    }

    profile.reminderTimeInSeconds = reminderTime
    profile.customReminderMessage = customReminderMessage
    profile.updatedAt = Date()

    // Update the snapshot
    updateSnapshot(for: profile)

    try context.save()

    return profile
  }

  static func deleteProfile(
    _ profile: BlockedProfiles,
    in context: ModelContext
  ) throws {
    // First end any active sessions
    for session in profile.sessions {
      if session.endTime == nil {
        session.endSession()
      }
    }

    // Remove all sessions first
    for session in profile.sessions {
      context.delete(session)
    }

    // Delete the snapshot
    deleteSnapshot(for: profile)

    // Remove the schedule restrictions
    DeviceActivityCenterUtil.removeScheduleTimerActivities(for: profile)

    // Then delete the profile
    context.delete(profile)
    // Defer context saving as the reference to the profile might be used
  }

  static func getProfileDeepLink(_ profile: BlockedProfiles) -> String {
    return "https://ctrus.pt/profile/" + profile.id.uuidString
  }

  static func getSnapshot(for profile: BlockedProfiles) -> SharedData.ProfileSnapshot {
    return SharedData.ProfileSnapshot(
      id: profile.id,
      name: profile.name,
      selectedActivity: profile.selectedActivity,
      createdAt: profile.createdAt,
      updatedAt: profile.updatedAt,
      blockingStrategyId: profile.blockingStrategyId,
      strategyData: profile.strategyData,
      order: profile.order,
      enableLiveActivity: profile.enableLiveActivity,
      reminderTimeInSeconds: profile.reminderTimeInSeconds,
      customReminderMessage: profile.customReminderMessage,
      enableBreaks: profile.enableBreaks,
      breakTimeInMinutes: profile.breakTimeInMinutes,
      allowMultipleBreaks: profile.allowMultipleBreaks,
      enableStrictMode: profile.enableStrictMode,
      enableBlockAppInstallation: profile.enableBlockAppInstallation,
      enableAllowMode: profile.enableAllowMode,
      enableAllowModeDomains: profile.enableAllowModeDomains,
      enableSafariBlocking: profile.enableSafariBlocking,
      enableAdultContentBlocking: profile.enableAdultContentBlocking,
      domains: profile.domains,
      physicalUnblockNFCTagId: nil,
      physicalUnblockItems: profile.physicalUnblockItems,
      schedule: profile.schedule,
      allowSkip: profile.allowSkip,
      skipNextOccurrence: profile.skipNextOccurrence,
      skipUntil: profile.skipUntil,
      childTag: profile.childTag,
      childTagCanStop: profile.childTagCanStop,
      disableBackgroundStops: profile.disableBackgroundStops,
      enableEmergencyUnblock: profile.enableEmergencyUnblock
    )
  }

  static func updateScheduleSkip(
    _ profile: BlockedProfiles,
    to skip: ScheduleSkip,
    in context: ModelContext
  ) throws {
    profile.skipNextOccurrence = skip.skipNextOccurrence
    profile.skipUntil = skip.skipUntil

    updateSnapshot(for: profile)
    try context.save()

    DeviceActivityCenterUtil.refreshUpcomingSessionReminders(for: profile)
  }

  static func clearExpiredScheduleSkips(in context: ModelContext) {
    guard let profiles = try? fetchProfiles(in: context) else { return }

    for profile in profiles {
      let skip = profile.scheduleSkip
      let activeSkip = skip.clearingExpired()
      guard activeSkip != skip else { continue }

      try? updateScheduleSkip(profile, to: activeSkip, in: context)
    }
  }

  // Create a codable/equatable snapshot suitable for UserDefaults
  static func updateSnapshot(for profile: BlockedProfiles) {
    let snapshot = getSnapshot(for: profile)
    SharedData.setSnapshot(snapshot, for: profile.id.uuidString)
  }

  static func deleteSnapshot(for profile: BlockedProfiles) {
    SharedData.removeSnapshot(for: profile.id.uuidString)
  }

  static func reorderProfiles(
    _ profiles: [BlockedProfiles],
    in context: ModelContext
  ) throws {
    for (index, profile) in profiles.enumerated() {
      profile.order = index
    }
    try context.save()
  }

  static func getNextOrder(in context: ModelContext) -> Int {
    let descriptor = FetchDescriptor<BlockedProfiles>(
      sortBy: [SortDescriptor(\.order, order: .reverse)]
    )
    guard let lastProfile = try? context.fetch(descriptor).first else {
      return 0
    }
    return lastProfile.order + 1
  }

  static func createProfile(
    in context: ModelContext,
    name: String,
    selection: FamilyActivitySelection = FamilyActivitySelection(),
    blockingStrategyId: String = NFCBlockingStrategy.id,
    strategyData: Data? = nil,
    enableLiveActivity: Bool = false,
    reminderTimeInSeconds: UInt32? = nil,
    customReminderMessage: String = "",
    enableBreaks: Bool = false,
    breakTimeInMinutes: Int = 10,
    allowMultipleBreaks: Bool = false,
    enableStrictMode: Bool = false,
    enableBlockAppInstallation: Bool = false,
    enableAllowMode: Bool = false,
    enableAllowModeDomains: Bool = false,
    enableSafariBlocking: Bool = true,
    enableAdultContentBlocking: Bool = false,
    domains: [String]? = nil,
    physicalUnblockItems: [PhysicalUnblockItem]? = nil,
    schedule: BlockedProfileSchedule? = nil,
    allowSkip: Bool = false,
    enableSnooze: Bool = true,
    isOneTimeAlarm: Bool = false,
    childTag: ChildTag? = nil,
    childTagCanStop: Bool = false,
    disableBackgroundStops: Bool = false,
    enableEmergencyUnblock: Bool = true
  ) throws -> BlockedProfiles {
    let profileOrder = getNextOrder(in: context)

    let profile = BlockedProfiles(
      name: name,
      selectedActivity: selection,
      blockingStrategyId: blockingStrategyId,
      strategyData: strategyData,
      enableLiveActivity: enableLiveActivity,
      reminderTimeInSeconds: reminderTimeInSeconds,
      customReminderMessage: customReminderMessage,
      enableBreaks: enableBreaks,
      breakTimeInMinutes: breakTimeInMinutes,
      allowMultipleBreaks: allowMultipleBreaks,
      enableStrictMode: enableStrictMode,
      enableBlockAppInstallation: enableBlockAppInstallation,
      enableAllowMode: enableAllowMode,
      enableAllowModeDomains: enableAllowModeDomains,
      enableSafariBlocking: enableSafariBlocking,
      enableAdultContentBlocking: enableAdultContentBlocking,
      order: profileOrder,
      domains: domains,
      physicalUnblockItems: physicalUnblockItems,
      disableBackgroundStops: disableBackgroundStops,
      enableEmergencyUnblock: enableEmergencyUnblock
    )

    if let schedule = schedule {
      profile.schedule = schedule
    }
    profile.allowSkip = allowSkip
    profile.enableSnooze = enableSnooze
    profile.isOneTimeAlarm = isOneTimeAlarm
    profile.childTag = childTag
    profile.childTagCanStop = childTagCanStop

    // Create the snapshot so extensions can read it immediately
    updateSnapshot(for: profile)

    context.insert(profile)
    try context.save()
    return profile
  }

  static func cloneProfile(
    _ source: BlockedProfiles,
    in context: ModelContext,
    newName: String
  ) throws -> BlockedProfiles {
    let nextOrder = getNextOrder(in: context)
    let cloned = BlockedProfiles(
      name: newName,
      selectedActivity: source.selectedActivity,
      blockingStrategyId: source.blockingStrategyId ?? NFCBlockingStrategy.id,
      strategyData: source.strategyData,
      enableLiveActivity: source.enableLiveActivity,
      reminderTimeInSeconds: source.reminderTimeInSeconds,
      customReminderMessage: source.customReminderMessage,
      enableBreaks: source.enableBreaks,
      breakTimeInMinutes: source.breakTimeInMinutes,
      allowMultipleBreaks: source.allowMultipleBreaks,
      enableStrictMode: source.enableStrictMode,
      enableBlockAppInstallation: source.enableBlockAppInstallation,
      enableAllowMode: source.enableAllowMode,
      enableAllowModeDomains: source.enableAllowModeDomains,
      enableSafariBlocking: source.enableSafariBlocking,
      enableAdultContentBlocking: source.enableAdultContentBlocking,
      order: nextOrder,
      domains: source.domains,
      physicalUnblockItems: source.physicalUnblockItems,
      schedule: source.schedule,
      enableEmergencyUnblock: source.enableEmergencyUnblock
    )
    cloned.allowSkip = source.allowSkip
    cloned.enableSnooze = source.enableSnooze
    cloned.isOneTimeAlarm = source.isOneTimeAlarm
    cloned.childTag = source.childTag
    cloned.childTagCanStop = source.childTagCanStop

    context.insert(cloned)
    try context.save()
    return cloned
  }

  static func addDomain(to profile: BlockedProfiles, context: ModelContext, domain: String) throws {
    guard let domains = profile.domains else {
      return
    }

    if domains.contains(domain) {
      return
    }

    let newDomains = domains + [domain]
    try updateProfile(profile, in: context, domains: newDomains)
  }

  static func removeDomain(from profile: BlockedProfiles, context: ModelContext, domain: String)
    throws
  {
    guard let domains = profile.domains else {
      return
    }

    let newDomains = domains.filter { $0 != domain }
    try updateProfile(profile, in: context, domains: newDomains)
  }
}
