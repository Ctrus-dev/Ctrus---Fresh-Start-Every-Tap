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
  // material, never painted as a flat fill. The "*Light" materials turned out to be
  // dominated by their own near-white base regardless of how saturated/dark a color
  // we fed them (tried both systemThickMaterialLight and systemThinMaterialLight —
  // both read as pale/washed). "*Dark" materials let the actual hue through much more,
  // at the cost of darkening it, so `.systemThinMaterialDark` (below) + boosting
  // saturation/brightness here to compensate for that darkening should land closer to
  // the true theme color. Re-tune these two factors against a real device if it's
  // still off.
  private static let shieldColorSaturationBoost: CGFloat = 1.2
  private static let shieldColorBrightnessBoost: CGFloat = 1.5

  private static func fixedBrandColor(_ color: Color) -> UIColor {
    var hue: CGFloat = 0
    var saturation: CGFloat = 0
    var brightness: CGFloat = 0
    var alpha: CGFloat = 0
    UIColor(color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

    let boosted = UIColor(
      hue: hue,
      saturation: min(saturation * shieldColorSaturationBoost, 1),
      brightness: min(brightness * shieldColorBrightnessBoost, 1),
      alpha: alpha
    )
    // Resolve to a plain, non-dynamic UIColor so the value can't get re-resolved
    // against a different trait collection when it crosses into the system's
    // shield-rendering process.
    return UIColor { _ in boosted }
  }

  override func configuration(shielding application: Application) -> ShieldConfiguration {
    if let softUnblockConfiguration = softUnblockConfiguration(for: application, in: nil) {
      return softUnblockConfiguration
    }

    return createCustomShieldConfiguration(
      for: .app, title: application.localizedDisplayName ?? String(localized: "App"))
  }

  override func configuration(shielding application: Application, in category: ActivityCategory)
    -> ShieldConfiguration
  {
    if let softUnblockConfiguration = softUnblockConfiguration(for: application, in: category) {
      return softUnblockConfiguration
    }

    return createCustomShieldConfiguration(
      for: .app, title: application.localizedDisplayName ?? String(localized: "App"))
  }

  override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
    return createCustomShieldConfiguration(
      for: .website, title: webDomain.domain ?? String(localized: "Website"))
  }

  override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory)
    -> ShieldConfiguration
  {
    return createCustomShieldConfiguration(
      for: .website, title: webDomain.domain ?? String(localized: "Website"))
  }

  private func createCustomShieldConfiguration(for type: BlockedContentType, title: String)
    -> ShieldConfiguration
  {
    // Get user's selected theme color
    let brandColor = Self.fixedBrandColor(ThemeManager.shared.themeColor)

    // Get random fun message
    let randomMessage = getFunBlockMessage(for: type, title: title)

    // Emoji “icon” (rendered to an image so it works with ShieldConfiguration.icon)
    let emojiIcon = makeEmojiIcon(Self.lockEmoji, size: 96)

    return ShieldConfiguration(
      // `nil` here doesn't mean "no blur" — the system falls back to its own adaptive
      // material, which is what made this look dark brown in Dark Mode and pale cream
      // in Light Mode regardless of backgroundColor. `.systemThinMaterialDark` is a
      // *non-adaptive* material (always renders as its dark variant, regardless of the
      // system's own Light/Dark Mode setting), so the shield looks the same in both —
      // see the comment on `fixedBrandColor` above for why it's specifically "Dark".
      backgroundBlurStyle: .systemThinMaterialDark,
      backgroundColor: brandColor,
      icon: emojiIcon,
      title: ShieldConfiguration.Label(
        text: randomMessage.title,
        color: .white
      ),
      subtitle: ShieldConfiguration.Label(
        text: randomMessage.subtitle,
        color: UIColor.white.withAlphaComponent(0.88)
      ),
      primaryButtonLabel: ShieldConfiguration.Label(
        text: randomMessage.buttonText,
        color: .black
      ),
      primaryButtonBackgroundColor: .white,
      secondaryButtonLabel: nil
    )
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
      backgroundBlurStyle: .systemThinMaterialDark,
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
      backgroundBlurStyle: .systemThinMaterialDark,
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
        String(localized: "Not ripe yet"),
        String(localized: "\(title) can wait until you're ready to pick it."),
        String(localized: "Got it")
      ),
      (
        String(localized: "Juicy trap"),
        String(localized: "One click turns into twenty. Let's not squeeze this dry."),
        String(localized: "Got it")
      ),
      (
        String(localized: "Protect the grove"),
        String(localized: "A few minutes ripen into an hour before you know it."),
        String(localized: "Got it")
      ),
      (
        String(localized: "Nothing to peel"),
        String(localized: "Relax, you're not missing anything."),
        String(localized: "Got it")
      ),
      (
        String(localized: "Drop by drop"),
        String(localized: "Small squeezes of effort like this fill the glass fast."),
        String(localized: "Got it")
      ),
      (
        String(localized: "Sour now, sweet later"),
        String(localized: "This feeling fades faster than you think."),
        String(localized: "Got it")
      ),
      (
        String(localized: "Make lemonade"),
        String(localized: "When life gives you lemons, close \(title)."),
        String(localized: "Got it")
      ),
      (
        String(localized: "Grow somewhere better"),
        String(localized: "Your attention can bear more fruit elsewhere."),
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
