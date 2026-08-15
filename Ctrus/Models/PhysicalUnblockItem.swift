import Foundation

/// Represents a physical NFC tag that can unblock a profile
/// Supports having multiple NFC tags per profile
struct PhysicalUnblockItem: Codable, Hashable, Identifiable, Sendable {
  var id: UUID
  var name: String
  var type: PhysicalUnblockType
  var codeValue: String

  enum PhysicalUnblockType: String, Codable, CaseIterable, Sendable {
    case nfc = "nfc"

    var displayName: String {
      switch self {
      case .nfc: return String(localized: "NFC Tag")
      }
    }
  }

  init(
    id: UUID = UUID(),
    name: String,
    type: PhysicalUnblockType,
    codeValue: String
  ) {
    self.id = id
    self.name = name
    self.type = type
    self.codeValue = codeValue
  }

  static func resolvedItems(
    physicalUnblockItems: [PhysicalUnblockItem]?,
    legacyNFCTagId: String? = nil
  ) -> [PhysicalUnblockItem]? {
    if let physicalUnblockItems {
      return normalizedItems(physicalUnblockItems)
    }

    var items: [PhysicalUnblockItem] = []

    if let legacyNFCTagId, !legacyNFCTagId.isEmpty {
      items.append(
        PhysicalUnblockItem(
          name: String(localized: "NFC Tag"),
          type: .nfc,
          codeValue: legacyNFCTagId
        )
      )
    }

    return normalizedItems(items)
  }

  static func normalizedItems(_ items: [PhysicalUnblockItem]?) -> [PhysicalUnblockItem]? {
    guard let items else { return nil }

    let normalizedItems = items.compactMap { item -> PhysicalUnblockItem? in
      let trimmedName = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
      let normalizedCodeValue = normalizedCodeValue(item.codeValue, type: item.type)

      guard !normalizedCodeValue.isEmpty else { return nil }

      return PhysicalUnblockItem(
        id: item.id,
        name: trimmedName.isEmpty ? item.type.displayName : trimmedName,
        type: item.type,
        codeValue: normalizedCodeValue
      )
    }

    return normalizedItems.isEmpty ? nil : normalizedItems
  }

  static func normalizedCodeValue(
    _ codeValue: String,
    type: PhysicalUnblockType
  ) -> String {
    return codeValue.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
