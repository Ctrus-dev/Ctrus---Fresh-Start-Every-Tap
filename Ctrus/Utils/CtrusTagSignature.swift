import CoreNFC
import CryptoKit
import Foundation

/// Tells a real Ctrus from any other NFC tag. Each Ctrus carries a signature
/// of its tag's factory UID, made with a key only the maker has; copying it to
/// another tag doesn't work, as that tag's UID is different.
enum CtrusTagSignature {
  /// NDEF external type of the record holding the signature.
  static let recordType = "ctrus.pt:sig"

  private static let publicKey = try! P256.Signing.PublicKey(
    rawRepresentation: Data(
      base64Encoded:
        "Z2dxTxUA+sYV9MsI8Lidphw0CK8XOY6MG4WpnlGu+YhczCW/wi5m2JwAlEOHQ3zq3HGCI8ydoqyjhApDxskoBA=="
    )!)

  static func message(forUID uid: Data) -> Data {
    Data("ctrus-tag-v1:".utf8) + uid
  }

  static func isGenuine(uid: Data, message: NFCNDEFMessage?) -> Bool {
    guard let record = message?.records.first(where: isSignatureRecord),
      let signature = try? P256.Signing.ECDSASignature(rawRepresentation: record.payload)
    else {
      return false
    }
    return publicKey.isValidSignature(signature, for: self.message(forUID: uid))
  }

  static func record(signature: Data) -> NFCNDEFPayload {
    NFCNDEFPayload(
      format: .nfcExternal,
      type: Data(recordType.utf8),
      identifier: Data(),
      payload: signature
    )
  }

  private static func isSignatureRecord(_ record: NFCNDEFPayload) -> Bool {
    record.typeNameFormat == .nfcExternal && record.type == Data(recordType.utf8)
  }
}
