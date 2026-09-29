import SwiftData
import SwiftUI

// Backs the "Schedule" option in profile creation. ScheduleTimerActivity
// starts a session automatically at the configured days/time through
// DeviceActivityCenter, but never ends one — stopping always goes through
// this strategy's NFC scan, same as tapping "Stop" would for any other
// physically-unlocked profile.
class ScheduleBlockingStrategy: BlockingStrategy {
  static var id: String = "ScheduleBlockingStrategy"

  var name: String = String(localized: "Schedule + Ctrus NFC")
  var description: String = String(
    localized:
      "Set the time and days of the week this profile should start automatically. You'll need your Ctrus to end it before time is up."
  )
  var color: Color = .green
  var pickerCategory: BlockingStrategyPickerCategory = .mostPopular

  var usesNFC: Bool = true
  var startsManually: Bool = true

  var tags: [BlockingStrategyTag] {
    [.automaticStart, .nfc]
  }

  var onSessionCreation: ((SessionStatus) -> Void)?
  var onErrorMessage: ((String) -> Void)?

  private let nfcScanner: NFCScannerUtil = NFCScannerUtil()
  private let appBlocker: AppBlockerUtil = AppBlockerUtil()

  func getIdentifier() -> String {
    return ScheduleBlockingStrategy.id
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
        withTag: ScheduleBlockingStrategy.id,
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
