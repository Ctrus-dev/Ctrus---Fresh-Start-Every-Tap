//
//  ShieldConfigurationExtension.swift
//  CtrusShieldConfig
//
//  Created by Ali Waseem on 2025-08-11.
//

import ManagedSettings
import ManagedSettingsUI
import SwiftUI
import UIKit

// Override the functions below to customize the shields used in various situations.
// The system provides a default appearance for any methods that your subclass doesn't override.
// Make sure that your class name matches the NSExtensionPrincipalClass in your Info.plist.
class ShieldConfigurationExtension: ShieldConfigurationDataSource {
  private static let lockEmoji = "🔒"

  // Apple documents `ShieldConfiguration.backgroundColor` as "a color for a shield to
  // use in the background BLUR effect" — it's always mixed into a frosted-glass
  // material, never painted as a flat fill; there is no way to turn the blur off. The
  // App Switcher's card preview of a shield shows this same color RAW (unblurred) right
  // at its rounded corners, with the blurred, darker body everywhere else — so boosting
  // saturation/brightness to compensate for the blur's darkening (tried earlier) made
  // that raw corner sliver far more vivid than the body, a visibly mismatched seam.
  // Passing the color through unmodified, like the original Foqos shield did, keeps
  // the corner and the body close enough that the seam isn't noticeable — at the cost
  // of the body itself reading a bit more muted/dark than the true theme color, which
  // is an unavoidable tradeoff: boost it and the corners clash, don't and the body is
  // duller. `.dark` (below) is what Foqos used too.
  private static func fixedBrandColor(_ color: Color) -> UIColor {
    let resolved = UIColor(color).resolvedColor(
      with: UITraitCollection(userInterfaceStyle: .light))
    // Resolve to a plain, non-dynamic UIColor so the value can't get re-resolved
    // against a different trait collection when it crosses into the system's
    // shield-rendering process.
    return UIColor { _ in resolved }
  }

  override func configuration(shielding application: Application) -> ShieldConfiguration {
    if let softUnblockConfiguration = softUnblockConfiguration(for: application, in: nil) {
      return softUnblockConfiguration
    }

    return themedStockConfiguration()
  }

  override func configuration(shielding application: Application, in category: ActivityCategory)
    -> ShieldConfiguration
  {
    if let softUnblockConfiguration = softUnblockConfiguration(for: application, in: category) {
      return softUnblockConfiguration
    }

    return themedStockConfiguration()
  }

  override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
    themedStockConfiguration()
  }

  override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory)
    -> ShieldConfiguration
  {
    themedStockConfiguration()
  }

  // Only the icon and the button take the theme color; everything else is left nil
  // in the hope that the system fills in its own background, localized title, subtitle
  // and "OK" label, the same as the stock shield.
  private func themedStockConfiguration() -> ShieldConfiguration {
    let brandColor = Self.fixedBrandColor(ThemeManager.shared.themeColor)
    return ShieldConfiguration(
      icon: makeBlockedIcon(color: brandColor),
      primaryButtonBackgroundColor: brandColor
    )
  }

  private func makeBlockedIcon(color: UIColor) -> UIImage? {
    let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 64, weight: .regular)
    return UIImage(systemName: "nosign", withConfiguration: symbolConfiguration)?
      .withTintColor(color, renderingMode: .alwaysOriginal)
  }

  private func softUnblockConfiguration(
    for application: Application,
    in category: ActivityCategory?
  ) -> ShieldConfiguration? {
    guard let session = SoftUnblockGrantStore.activeSession,
      let snapshot = SharedData.snapshot(for: session.profileId.uuidString),
      let presentation = softUnblockPresentation(
        for: application,
        in: category,
        profile: snapshot
      ),
      !SoftUnblockGrantStore.hasActiveGrant(
        for: presentation.resource,
        profileId: session.profileId
      )
    else {
      return nil
    }

    let configuration = SoftUnblockStrategyData.decode(snapshot.strategyData)
    guard session.remainingUnblockCount > 0 else {
      return exhaustedSoftUnblockConfiguration(session: session)
    }

    let accessMinutes = configuration.accessDurationInMinutes
    let buttonText = String(localized: "Open for \(accessMinutes)m")
    let randomMessage = getFunBlockMessage(
      for: .app,
      title: application.localizedDisplayName ?? presentation.resourceName
    )
    var allowanceLines = [
      String(
        localized:
          "\(presentation.resourceName) (\(session.remainingUnblockCount)/\(session.maximumUnblockCount))"
      ),
      breakAllowanceIndicator(for: session),
    ]
    if let resetDescription = allowanceResetDescription(for: session) {
      allowanceLines.append(resetDescription)
    }
    let subtitle = [randomMessage.subtitle, allowanceLines.joined(separator: "\n")]
      .joined(separator: "\n\n")

    return ShieldConfiguration(
      backgroundBlurStyle: .dark,
      backgroundColor: Self.fixedBrandColor(ThemeManager.shared.themeColor),
      icon: makeEmojiIcon(Self.lockEmoji, size: 96),
      title: ShieldConfiguration.Label(
        text: randomMessage.title,
        color: .white
      ),
      subtitle: ShieldConfiguration.Label(
        text: subtitle,
        color: UIColor.white.withAlphaComponent(0.88)
      ),
      primaryButtonLabel: ShieldConfiguration.Label(
        text: buttonText,
        color: .black
      ),
      primaryButtonBackgroundColor: .white,
      secondaryButtonLabel: ShieldConfiguration.Label(
        text: String(localized: "Back"),
        color: .white
      )
    )
  }

  private func exhaustedSoftUnblockConfiguration(
    session: SoftUnblockSessionState
  ) -> ShieldConfiguration {
    let usageText =
      session.maximumUnblockCount == 1
      ? String(localized: "You already used your open for this session.")
      : String(localized: "You used all \(session.maximumUnblockCount) opens for this session.")
    let subtitle = [usageText, allowanceResetDescription(for: session)]
      .compactMap { $0 }
      .joined(separator: " ")

    return ShieldConfiguration(
      backgroundBlurStyle: .dark,
      backgroundColor: Self.fixedBrandColor(ThemeManager.shared.themeColor),
      icon: makeEmojiIcon(Self.lockEmoji, size: 96),
      title: ShieldConfiguration.Label(
        text: String(localized: "No opens left"),
        color: .white
      ),
      subtitle: ShieldConfiguration.Label(
        text: subtitle,
        color: UIColor.white.withAlphaComponent(0.88)
      ),
      primaryButtonLabel: ShieldConfiguration.Label(
        text: String(localized: "Back"),
        color: .black
      ),
      primaryButtonBackgroundColor: .white,
      secondaryButtonLabel: nil
    )
  }

  private func allowanceResetDescription(for session: SoftUnblockSessionState) -> String? {
    guard session.allowanceResetIntervalInHours != nil,
      let nextAllowanceResetAt = session.nextAllowanceResetAt
    else {
      return nil
    }

    let remainingMinutes = max(
      Int(ceil(nextAllowanceResetAt.timeIntervalSinceNow / 60)),
      1
    )
    if remainingMinutes >= 60 {
      return String(localized: "Resets in \(remainingMinutes / 60)h")
    }
    return String(localized: "Resets in \(remainingMinutes)m")
  }

  private func breakAllowanceIndicator(for session: SoftUnblockSessionState) -> String {
    let availableBreaks = Array(
      repeating: "●",
      count: session.remainingUnblockCount
    )
    let usedBreaks = Array(
      repeating: "○",
      count: session.maximumUnblockCount - session.remainingUnblockCount
    )
    return (availableBreaks + usedBreaks).joined(separator: "  ")
  }

  private func softUnblockPresentation(
    for application: Application,
    in category: ActivityCategory?,
    profile: SharedData.ProfileSnapshot
  ) -> (resource: SoftUnblockResource, resourceName: String)? {
    if let categoryToken = category?.token {
      guard !profile.enableAllowMode else { return nil }

      let categoryName = category?.localizedDisplayName ?? String(localized: "this category")
      return (
        resource: .category(categoryToken),
        resourceName: categoryName
      )
    }

    guard let applicationToken = application.token else { return nil }
    let applicationName = application.localizedDisplayName ?? String(localized: "this app")
    return (
      resource: .application(applicationToken),
      resourceName: applicationName
    )
  }

  private func getFunBlockMessage(for _: BlockedContentType, title: String) -> (
    title: String, subtitle: String, buttonText: String
  ) {
    typealias FunMessage = (title: String, subtitle: String, buttonText: String)

    // Curated citrus-themed messages shown on the block screen.
    let messages: [FunMessage] = [
      (
        String(localized: "Life gave you lemons…"),
        String(localized: "And you want to turn them into doomscrolling."),
        String(localized: "Got it")
      ),
      (
        String(localized: "100% juice, they say…"),
        String(localized: "Your focus is running at 0%."),
        String(localized: "Got it")
      ),
      (
        String(localized: "Vitamin C doesn't work like this!"),
        String(localized: "A daily dose of \(title) won't do you any good."),
        String(localized: "Got it")
      ),
      (
        String(localized: "When life gives you lemons…"),
        String(localized: "You really think this is the lemonade?"),
        String(localized: "Got it")
      ),
      (
        String(localized: "The tree takes time to bear fruit…"),
        String(localized: "You keep coming back to \(title) whenever you want, that's the problem."),
        String(localized: "Got it")
      ),
      (
        String(localized: "Sweet on the outside…"),
        String(localized: "Bitter when you realize how many hours you've already spent here."),
        String(localized: "Got it")
      ),
      (
        String(localized: "Looks harmless on the outside…"),
        String(localized: "You know it's bitter on the inside."),
        String(localized: "Got it")
      ),
      (
        String(localized: "Good things take time to ripen!"),
        String(localized: "\(title) isn't one of them."),
        String(localized: "Got it")
      ),
      (
        String(localized: "Here we are again…"),
        String(localized: "This is getting repetitive, and not in a sweet way."),
        String(localized: "Got it")
      ),
    ]
    guard !messages.isEmpty else {
      return (
        String(localized: "Quick pause"), String(localized: "Not right now"),
        String(localized: "Back")
      )
    }

    let comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    let dayKey =
      (comps.year ?? 0) * 10_000
      + (comps.month ?? 0) * 100
      + (comps.day ?? 0)

    let seed = Int(stableSeed(for: title) % UInt64(Int.max)) ^ dayKey
    let idx = abs(seed) % messages.count

    return messages[idx]
  }

  private func stableSeed(for title: String) -> UInt64 {
    // FNV-1a 64-bit over unicode scalars (deterministic across runs/devices).
    var hash: UInt64 = 14_695_981_039_346_656_037
    for scalar in title.unicodeScalars {
      hash ^= UInt64(scalar.value)
      hash &*= 1_099_511_628_211
    }
    return hash
  }

  private func makeEmojiIcon(_ emoji: String, size: CGFloat) -> UIImage? {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
    return renderer.image { _ in
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = .center

      let attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: size * 0.78),
        .paragraphStyle: paragraph,
      ]

      let rect = CGRect(x: 0, y: 0, width: size, height: size)
      let attributed = NSAttributedString(string: emoji, attributes: attributes)
      let bounds = attributed.boundingRect(
        with: rect.size,
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        context: nil
      )

      // Vertically center emoji
      let drawRect = CGRect(
        x: rect.minX,
        y: rect.minY + (rect.height - bounds.height) / 2,
        width: rect.width,
        height: bounds.height
      )
      attributed.draw(in: drawRect)
    }
  }
}

enum BlockedContentType {
  case app
  case website
}
