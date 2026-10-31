import Foundation

enum AppMode: String, Codable {
  case normal
  case child
}

/// One of the parents' Ctrus tags — the master key for every profile in
/// child mode. Recognised by its UID only: a URL can be copied onto any tag.
struct ParentTag: Codable, Equatable, Hashable, Identifiable {
  var uid: String
  var url: String?
  var label: String

  var id: String { uid }
}

/// The optional child's Ctrus on a profile. Starts sessions; ends them only
/// when the profile allows it.
struct ChildTag: Codable, Equatable, Hashable {
  var uid: String
  var url: String?
}

struct TamperLogEntry: Codable, Equatable, Identifiable {
  enum Kind: String, Codable {
    case permissionRevoked
    case clockChanged
    case pinLockout
  }

  var id = UUID()
  var type: Kind
  var at: Date
  /// How far the date moved away from real time; negative when moved back.
  var dateShift: TimeInterval?
  /// How long entering the parent code was locked for.
  var lockDuration: TimeInterval?
  /// The profile whose session was running at the time.
  var activeProfileName: String?

  var title: String {
    switch type {
    case .permissionRevoked: return String(localized: "Some permissions may have been turned off")
    case .clockChanged: return String(localized: "Phone date changed")
    case .pinLockout: return String(localized: "5 wrong codes in a row")
    }
  }

  var systemImage: String {
    switch type {
    case .permissionRevoked: return "shield.slash"
    case .clockChanged: return "clock.badge.exclamationmark"
    case .pinLockout: return "lock.fill"
    }
  }

  /// The specifics of this entry, in a line.
  var summary: String? {
    switch type {
    case .clockChanged:
      guard let dateShift else { return nil }
      let amount = Self.formattedDuration(abs(dateShift))
      return dateShift > 0
        ? String(localized: "Moved forward by about \(amount)")
        : String(localized: "Moved back by about \(amount)")
    case .pinLockout:
      guard let lockDuration else { return nil }
      return String(localized: "Code entry locked for \(Self.formattedDuration(lockDuration))")
    case .permissionRevoked:
      return nil
    }
  }

  var explanation: String {
    switch type {
    case .permissionRevoked:
      return String(
        localized:
          "Ctrus lost its Screen Time access. While it's off, Ctrus can't block any apps.")
    case .clockChanged:
      return String(
        localized: "The phone's date or time was changed by hand, away from the real time.")
    case .pinLockout:
      return String(
        localized:
          "Someone entered the wrong parent code 5 times in a row, so entering it was locked for a while."
      )
    }
  }

  var advice: String {
    switch type {
    case .permissionRevoked:
      return String(
        localized:
          "It can be turned off in Settings › Screen Time, and is sometimes reset by an iOS update. Open Ctrus and allow access again so apps are blocked."
      )
    case .clockChanged:
      return String(
        localized:
          "Ctrus times sessions by the real time that has passed, so this doesn't end them sooner. Check that Set Automatically is on in Settings › General › Date & Time."
      )
    case .pinLockout:
      return String(
        localized:
          "If it wasn't you, your child may be trying to guess the code. If you think they know it, change it in Child Mode settings."
      )
    }
  }

  private static func formattedDuration(_ interval: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .full
    formatter.allowedUnits = [.day, .hour, .minute]
    formatter.maximumUnitCount = 1
    return formatter.string(from: max(60, interval)) ?? ""
  }
}

// Kept in the App Group so the device monitor, which ends child-mode
// sessions while the app is closed, sees the same mode and log. The parent
// code and recovery key are not here — they live in the Keychain.
enum ChildModeStore {
  private static let suite = UserDefaults(suiteName: "group.mo.dev.Ctrus")!

  static let maxTamperLogEntries = 50

  private enum Key: String {
    case appMode
    case parentTags
    case tamperLog
    case tamperLogUnseen
  }

  static var appMode: AppMode {
    get {
      suite.string(forKey: Key.appMode.rawValue).flatMap(AppMode.init(rawValue:)) ?? .normal
    }
    set { suite.set(newValue.rawValue, forKey: Key.appMode.rawValue) }
  }

  static var isChildMode: Bool {
    appMode == .child
  }

  static var parentTags: [ParentTag] {
    get { decoded([ParentTag].self, forKey: .parentTags) ?? [] }
    set { encode(newValue, forKey: .parentTags) }
  }

  static var tamperLog: [TamperLogEntry] {
    get { decoded([TamperLogEntry].self, forKey: .tamperLog) ?? [] }
    set { encode(newValue, forKey: .tamperLog) }
  }

  static var tamperLogUnseen: Bool {
    get { suite.bool(forKey: Key.tamperLogUnseen.rawValue) }
    set { suite.set(newValue, forKey: Key.tamperLogUnseen.rawValue) }
  }

  /// Lowercase hex with no separators, the one format both apps compare in.
  static func normalizedUID(_ uid: String) -> String {
    uid.lowercased().filter { $0.isHexDigit }
  }

  static func isParentTag(uid: String) -> Bool {
    let normalized = normalizedUID(uid)
    return parentTags.contains { normalizedUID($0.uid) == normalized }
  }

  static func logTamper(
    _ kind: TamperLogEntry.Kind,
    at date: Date = Date(),
    dateShift: TimeInterval? = nil,
    lockDuration: TimeInterval? = nil
  ) {
    guard isChildMode else { return }

    let activeProfileName = SharedData.getActiveSharedSession().flatMap {
      SharedData.snapshot(for: $0.blockedProfileId.uuidString)?.name
    }

    var log = tamperLog
    log.append(
      TamperLogEntry(
        type: kind,
        at: date,
        dateShift: dateShift,
        lockDuration: lockDuration,
        activeProfileName: activeProfileName
      ))
    if log.count > maxTamperLogEntries {
      log.removeFirst(log.count - maxTamperLogEntries)
    }
    tamperLog = log
    tamperLogUnseen = true
  }

  // A single watcher reads the clock only to spot date changes, so one change
  // is logged once rather than by every feature that later notices it.
  private static let clockWatch = TrustedClock(key: "clockWatch", defaults: suite)

  static func checkForClockChange() {
    let reading = clockWatch.read()
    if reading.clockJumped {
      logTamper(.clockChanged, dateShift: reading.dateShift)
    }
  }

  static func clearChildModeData() {
    appMode = .normal
    parentTags = []
    tamperLog = []
    tamperLogUnseen = false
  }

  private static func decoded<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
    guard let data = suite.data(forKey: key.rawValue) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }

  private static func encode<T: Encodable>(_ value: T, forKey key: Key) {
    if let data = try? JSONEncoder().encode(value) {
      suite.set(data, forKey: key.rawValue)
    }
  }
}
