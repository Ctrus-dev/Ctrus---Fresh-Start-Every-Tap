import Foundation

enum PauseActiveSessionError: LocalizedError, Equatable {
  case noActiveSession
  case unsupportedStrategy(profileName: String)
  case alreadyPaused(profileName: String)
  case breakActive(profileName: String)
  case schedulingFailed(profileName: String, reason: String)

  var errorDescription: String? {
    switch self {
    case .noActiveSession:
      return String(localized: "No active Ctrus session to pause.")
    case .unsupportedStrategy(let profileName):
      return String(localized: "\(profileName) does not use a strategy that supports pausing.")
    case .alreadyPaused(let profileName):
      return String(localized: "\(profileName) is already paused.")
    case .breakActive(let profileName):
      return String(localized: "End the active break before pausing \(profileName).")
    case .schedulingFailed(let profileName, let reason):
      return String(localized: "Could not pause \(profileName): \(reason)")
    }
  }
}
