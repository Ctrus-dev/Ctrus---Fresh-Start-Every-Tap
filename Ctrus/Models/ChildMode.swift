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

enum ScheduleEndMode: String, Codable {
  case parentTag
  case fixedTime
}

struct ScheduleEndTime: Codable, Equatable, Hashable {
  var hour: Int
  var minute: Int
}

struct TamperLogEntry: Codable, Equatable, Identifiable {
  enum Kind: String, Codable {
    case permissionRevoked
    case appStopped
    case clockChanged
    case pinLockout
  }

  var id = UUID()
  var type: Kind
  var at: Date

  var title: String {
    switch type {
    case .permissionRevoked: return String(localized: "Ctrus permission turned off")
    case .appStopped: return String(localized: "Ctrus was stopped during a session")
    case .clockChanged: return String(localized: "Phone date changed")
    case .pinLockout: return String(localized: "5 wrong codes in a row")
    }
  }
}

// Kept in the App Group so the device monitor, which ends child-mode
// sessions while the app is closed, sees the same mode and log. The parent
// code and recovery key are not here — they live in the Keychain.
enum ChildModeStore {
  private static let suite = UserDefaults(suiteName: "group.mo.dev.Ctrus")!

  static let maxParentTags = 3
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

  static func logTamper(_ kind: TamperLogEntry.Kind, at date: Date = Date()) {
    guard isChildMode else { return }

    var log = tamperLog
    log.append(TamperLogEntry(type: kind, at: date))
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
      logTamper(.clockChanged)
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
