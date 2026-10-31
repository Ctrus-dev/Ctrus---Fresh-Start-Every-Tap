import SwiftData
import SwiftUI

class NFCManualBlockingStrategy: BlockingStrategy {
  static var id: String = "NFCManualBlockingStrategy"

  var name: String = String(localized: "Manual + Ctrus NFC")
  var description: String = String(
    localized: "Start by pressing the session bubble in the app. You'll need your Ctrus to end it."
  )
  var color: Color = .yellow
  var pickerCategory: BlockingStrategyPickerCategory = .easyToStart

  var usesNFC: Bool = true
  var startsManually: Bool = true

  var tags: [BlockingStrategyTag] {
    [.manualStart, .nfc]
  }

  var onSessionCreation: ((SessionStatus) -> Void)?
  var onErrorMessage: ((String) -> Void)?

  private let nfcScanner: NFCScannerUtil = NFCScannerUtil()
  private let appBlocker: AppBlockerUtil = AppBlockerUtil()

  func getIdentifier() -> String {
    return NFCManualBlockingStrategy.id
  }

  func startBlocking(
    context: ModelContext,
    profile: BlockedProfiles,
    forceStart: Bool?
  ) -> (any View)? {
    self.appBlocker.activateRestrictions(for: BlockedProfiles.getSnapshot(for: profile))

    let activeSession =
      BlockedProfileSession
      .createSession(
        in: context,
        // Manually starting sessions, since nothing was scanned to start there is no tag to store for each session
        withTag: ManualBlockingStrategy.id,
        withProfile: profile,
        forceStart: forceStart ?? false
      )

    self.onSessionCreation?(.started(activeSession))

    return nil
  }

  func stopBlocking(
    context: ModelContext,
    session: BlockedProfileSession
  ) -> (any View)? {
    nfcScanner.onTagScanned = { scanned in
      let tag = scanned.url ?? scanned.id

      if ChildModeStore.isChildMode {
        guard session.blockedProfile.childModeAllowsEnding(withTagId: scanned.id) else {
          self.onErrorMessage?(
            String(localized: "This is not allowed to unblock this profile.")
          )
          return
        }
      } else if session.blockedProfile.hasPhysicalUnblockItem(ofType: .nfc)
        && !session.blockedProfile.canUnblock(withCode: tag, type: .nfc)
      {
        self.onErrorMessage?(
          String(localized: "This is not allowed to unblock this profile.")
        )
        return
      }

      session.endSession()
      try? context.save()
      self.appBlocker.deactivateRestrictions()

      self.onSessionCreation?(.ended(session.blockedProfile))
    }

    nfcScanner.scan(profileName: session.blockedProfile.name)

    return nil
  }
}
