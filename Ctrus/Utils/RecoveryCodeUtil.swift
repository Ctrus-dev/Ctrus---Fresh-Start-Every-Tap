import Foundation

enum RecoveryCodeVerification {
  case valid(recentUnlockCount: Int)
  case invalid
  case networkError
}

enum RecoveryCodeUtil {
  private static let suite = UserDefaults(
    suiteName: "group.mo.dev.Ctrus"
  )!

  private static let deviceIDKey = "recoveryCode.deviceID"
  private static let baseURL = URL(string: "https://recover.ctrus.net")!

  static var deviceID: String {
    if let existing = suite.string(forKey: deviceIDKey) {
      return existing
    }

    let newID = UUID().uuidString
    suite.set(newID, forKey: deviceIDKey)
    return newID
  }

  static func verifyRecoveryCode(_ code: String) async -> RecoveryCodeVerification {
    guard let request = verifyRequest(code: code) else {
      return .networkError
    }

    guard let (data, response) = try? await URLSession.shared.data(for: request),
      let httpResponse = response as? HTTPURLResponse,
      httpResponse.statusCode == 200,
      let result = try? JSONDecoder().decode(VerifyResponse.self, from: data)
    else {
      return .networkError
    }

    guard result.valid else {
      return .invalid
    }

    return .valid(recentUnlockCount: result.recentUnlockCount ?? 1)
  }

  private static func verifyRequest(code: String) -> URLRequest? {
    let body = VerifyRequestBody(deviceId: deviceID, code: code)
    guard let bodyData = try? JSONEncoder().encode(body) else { return nil }

    var request = URLRequest(url: baseURL.appendingPathComponent("verify-code"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = bodyData
    return request
  }

  private struct VerifyRequestBody: Encodable {
    let deviceId: String
    let code: String
  }

  private struct VerifyResponse: Decodable {
    let valid: Bool
    let recentUnlockCount: Int?
  }
}
