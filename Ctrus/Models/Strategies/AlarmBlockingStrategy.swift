import SwiftData
import SwiftUI

// Backs "Alarm + Ctrus NFC": starts on its own like Schedule, but instead of
// ending at the end time it rings an alarm (WakeAlarmManager) that only the
// Ctrus or an emergency unblock silences — both of which end the session.
class AlarmBlockingStrategy: BlockingStrategy {
  static var id: String = "AlarmBlockingStrategy"

  var name: String = String(localized: "Alarm + Ctrus NFC")
  var description: String = String(
    localized:
      "Blocks your apps overnight. In the morning an alarm rings that only stops with your Ctrus."
  )
  var color: Color = .green
  var pickerCategory: BlockingStrategyPickerCategory = .mostPopular

  var usesNFC: Bool = true
  var startsManually: Bool = false
  var allowsTimedBreaks: Bool = true

  var tags: [BlockingStrategyTag] {
    [.automaticStart, .nfc]
  }

  var onSessionCreation: ((SessionStatus) -> Void)?
  var onErrorMessage: ((String) -> Void)?

  private let nfcScanner: NFCScannerUtil = NFCScannerUtil()
  private let appBlocker: AppBlockerUtil = AppBlockerUtil()

  func getIdentifier() -> String {
    return AlarmBlockingStrategy.id
  }

  func startBlocking(
    context: ModelContext,
    profile: BlockedProfiles,
    forceStart: Bool?
  ) -> (any View)? {
    // Like Schedule, it only ever starts on its own at the start time.
    self.onErrorMessage?(
      String(
        localized:
          "This profile starts on its own at its scheduled time — it can't be started manually.")
    )
    return nil
  }

  func stopBlocking(
    context: ModelContext,
    session: BlockedProfileSession
  ) -> (any View)? {
    nfcScanner.onTagScanned = { tag in
      let tag = tag.url ?? tag.id

      if session.blockedProfile.hasPhysicalUnblockItem(ofType: .nfc)
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
