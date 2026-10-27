import SwiftData
import SwiftUI

// Skipping only ever removes blocking, so it takes a tap of one of the
// profile's own tags — the same ones that can end its session. Resuming only
// adds blocking back, so it doesn't.
final class ScheduleSkipUtil {
  private let nfcScanner = NFCScannerUtil()

  func skipNextOccurrence(
    of profile: BlockedProfiles,
    in context: ModelContext,
    onSuccess: @escaping (String) -> Void,
    onError: @escaping (String) -> Void
  ) {
    guard let nextStart = profile.schedule?.nextStartDate(bufferSeconds: 0) else { return }

    authorize(profile, onError: onError) {
      var skip = profile.scheduleSkip
      skip.skipNextOccurrence = nextStart

      do {
        try BlockedProfiles.updateScheduleSkip(profile, to: skip, in: context)
        let occurrence = Self.occurrenceText(for: nextStart)
        onSuccess(String(localized: "Done. The session on \(occurrence) won't start."))
      } catch {
        onError(String(localized: "Failed to save changes: \(error.localizedDescription)"))
      }
    }
  }

  func skipUntil(
    _ day: Date,
    of profile: BlockedProfiles,
    in context: ModelContext,
    onSuccess: @escaping (String) -> Void,
    onError: @escaping (String) -> Void
  ) {
    let calendar = Calendar.current
    let lastSkippedDay = calendar.startOfDay(for: day)
    let backOn = calendar.date(byAdding: .day, value: 1, to: lastSkippedDay) ?? lastSkippedDay

    authorize(profile, onError: onError) {
      var skip = profile.scheduleSkip
      skip.skipUntil = lastSkippedDay

      do {
        try BlockedProfiles.updateScheduleSkip(profile, to: skip, in: context)
        let backOnText = Self.shortDayText(for: backOn)
        onSuccess(String(localized: "Done. The schedule is back on \(backOnText)."))
      } catch {
        onError(String(localized: "Failed to save changes: \(error.localizedDescription)"))
      }
    }
  }

  func resume(_ profile: BlockedProfiles, in context: ModelContext) {
    try? BlockedProfiles.updateScheduleSkip(profile, to: ScheduleSkip(), in: context)
  }

  private func authorize(
    _ profile: BlockedProfiles,
    onError: @escaping (String) -> Void,
    onAuthorized: @escaping () -> Void
  ) {
    nfcScanner.onTagScanned = { tag in
      let code = tag.url ?? tag.id

      guard profile.canUnblock(withCode: code, type: .nfc) else {
        onError(String(localized: "This Ctrus isn't linked to this profile."))
        return
      }

      onAuthorized()
    }

    nfcScanner.scan(profileName: profile.name)
  }

  // MARK: - Dates as shown to the person, in their own locale

  static func shortDayText(for date: Date) -> String {
    formatted(date, template: "dMMM")
  }

  static func weekdayAndDayText(for date: Date) -> String {
    formatted(date, template: "EEEEdMMM")
  }

  static func occurrenceText(for date: Date) -> String {
    formatted(date, template: "EEEEdMMMjm")
  }

  private static func formatted(_ date: Date, template: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale.autoupdatingCurrent
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter.string(from: date)
  }
}
