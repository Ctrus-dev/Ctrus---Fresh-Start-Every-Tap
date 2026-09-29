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
  var startsManually: Bool = false

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
    // Schedule mode only ever starts automatically, through
    // ScheduleTimerActivity — which never calls this function, it manipulates
    // the shared session state directly from the background extension.
    // Reaching this method at all means something tried to start it by hand
    // (hold-to-start, the start picker, a future entry point); a manual start
    // would run for whatever's left of the originally configured wall-clock
    // window rather than the chosen duration, so it's refused outright
    // instead of starting something the clock/auto-stop can't track
    // correctly.
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
