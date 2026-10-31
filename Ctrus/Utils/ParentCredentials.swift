import CommonCrypto
import Foundation
import Security

// The parent code and the recovery key, stored only as salted PBKDF2 hashes
// in the Keychain. Wrong guesses lock entry for a while; the wait is counted
// in real time by TrustedClock, so restarting the phone or moving its date
// doesn't shorten it.
enum ParentCredentials {
  static let codeLength = 6
  static let recoveryKeyLength = 12
  static let recoveryKeyAlphabet = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")

  static let attemptsBeforeLock = 5
  static let lockDurations: [TimeInterval] = [60, 5 * 60, 15 * 60, 60 * 60]

  private static let iterations: UInt32 = 100_000
  private static let saltLength = 16

  enum Secret: String {
    case parentCode
    case recoveryKey

    fileprivate var hashAccount: String { "\(rawValue)Hash" }
    fileprivate var saltAccount: String { "\(rawValue)Salt" }
    fileprivate var failedAttemptsKey: String { "\(rawValue)FailedAttempts" }
    fileprivate var lockLevelKey: String { "\(rawValue)LockLevel" }
    fileprivate var lockRemainingKey: String { "\(rawValue)LockRemaining" }
    fileprivate var lockClock: TrustedClock { TrustedClock(key: "\(rawValue)Lock") }
  }

  enum VerifyResult: Equatable {
    case valid
    case invalid
    case locked(remaining: TimeInterval)
  }

  // MARK: - Setting

  static func isWeakCode(_ code: String) -> Bool {
    guard code.count == codeLength, code.allSatisfy(\.isNumber) else { return true }

    let digits = code.compactMap(\.wholeNumberValue)
    let allSame = Set(digits).count == 1
    let ascending = zip(digits, digits.dropFirst()).allSatisfy { $1 == $0 + 1 }
    let descending = zip(digits, digits.dropFirst()).allSatisfy { $1 == $0 - 1 }
    return allSame || ascending || descending
  }

  static var hasParentCode: Bool {
    Keychain.read(account: Secret.parentCode.hashAccount) != nil
  }

  static func setParentCode(_ code: String) {
    store(code, as: .parentCode)
  }

  /// A fresh key, shown once as XXXX-XXXX-XXXX; only its hash is kept.
  static func makeRecoveryKey() -> String {
    let key = String(
      (0..<recoveryKeyLength).map { _ in recoveryKeyAlphabet.randomElement()! })
    store(key, as: .recoveryKey)
    return key
  }

  static func formattedRecoveryKey(_ key: String) -> String {
    stride(from: 0, to: key.count, by: 4)
      .map { offset -> String in
        let start = key.index(key.startIndex, offsetBy: offset)
        let end = key.index(start, offsetBy: 4, limitedBy: key.endIndex) ?? key.endIndex
        return String(key[start..<end])
      }
      .joined(separator: "-")
  }

  static func normalizedRecoveryKey(_ input: String) -> String {
    input.uppercased().filter { recoveryKeyAlphabet.contains($0) }
  }

  // MARK: - Checking

  static func verify(_ input: String, against secret: Secret) -> VerifyResult {
    let remaining = lockRemaining(for: secret)
    if remaining > 0 {
      return .locked(remaining: remaining)
    }

    let candidate = secret == .recoveryKey ? normalizedRecoveryKey(input) : input
    guard let storedHash = Keychain.read(account: secret.hashAccount),
      let salt = Keychain.read(account: secret.saltAccount),
      hash(candidate, salt: salt) == storedHash
    else {
      return registerFailure(for: secret)
    }

    resetAttempts(for: secret)
    return .valid
  }

  /// The parents' Ctrus always works, even during a wait, and clears it.
  static func resetAttempts(for secret: Secret) {
    let defaults = UserDefaults.standard
    defaults.set(0, forKey: secret.failedAttemptsKey)
    defaults.set(0, forKey: secret.lockLevelKey)
    defaults.set(0, forKey: secret.lockRemainingKey)
  }

  static func lockRemaining(for secret: Secret) -> TimeInterval {
    let defaults = UserDefaults.standard
    let elapsed = secret.lockClock.trustedElapsed()
    let remaining = max(0, defaults.double(forKey: secret.lockRemainingKey) - elapsed)
    defaults.set(remaining, forKey: secret.lockRemainingKey)
    return remaining
  }

  private static func registerFailure(for secret: Secret) -> VerifyResult {
    let defaults = UserDefaults.standard
    let failures = defaults.integer(forKey: secret.failedAttemptsKey) + 1

    guard failures >= attemptsBeforeLock else {
      defaults.set(failures, forKey: secret.failedAttemptsKey)
      return .invalid
    }

    let level = defaults.integer(forKey: secret.lockLevelKey)
    let duration = lockDurations[min(level, lockDurations.count - 1)]

    // Start the lock's clock now so the wait counts from this moment.
    _ = secret.lockClock.trustedElapsed()
    defaults.set(0, forKey: secret.failedAttemptsKey)
    defaults.set(level + 1, forKey: secret.lockLevelKey)
    defaults.set(duration, forKey: secret.lockRemainingKey)

    if secret == .parentCode {
      ChildModeStore.logTamper(.pinLockout)
    }

    return .locked(remaining: duration)
  }

  // MARK: - Clearing

  static func clearAll() {
    for secret in [Secret.parentCode, .recoveryKey] {
      Keychain.delete(account: secret.hashAccount)
      Keychain.delete(account: secret.saltAccount)
      resetAttempts(for: secret)
    }
  }

  // MARK: - Hashing

  private static func store(_ value: String, as secret: Secret) {
    var salt = Data(count: saltLength)
    _ = salt.withUnsafeMutableBytes {
      SecRandomCopyBytes(kSecRandomDefault, saltLength, $0.baseAddress!)
    }

    Keychain.write(salt, account: secret.saltAccount)
    Keychain.write(hash(value, salt: salt), account: secret.hashAccount)
    resetAttempts(for: secret)
  }

  private static func hash(_ value: String, salt: Data) -> Data {
    let password = Array(value.utf8).map { Int8(bitPattern: $0) }
    var derived = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))

    salt.withUnsafeBytes { saltBytes in
      _ = CCKeyDerivationPBKDF(
        CCPBKDFAlgorithm(kCCPBKDF2),
        password, password.count,
        saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
        iterations,
        &derived, derived.count
      )
    }

    return Data(derived)
  }
}

private enum Keychain {
  private static let service = "pt.ctrus.parentCredentials"

  static func read(account: String) -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
    return result as? Data
  }

  static func write(_ data: Data, account: String) {
    delete(account: account)

    let item: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      kSecValueData as String: data,
    ]
    SecItemAdd(item as CFDictionary, nil)
  }

  static func delete(account: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(query as CFDictionary)
  }
}
