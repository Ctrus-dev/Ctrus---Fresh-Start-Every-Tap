import CoreNFC
import SwiftUI

class PhysicalReader {
  private let nfcScanner: NFCScannerUtil = NFCScannerUtil()

  func readNFCTag(
    onSuccess: @escaping (String) -> Void,
    onFailure: @escaping (String) -> Void = { _ in }
  ) {
    nfcScanner.onTagScanned = { result in
      let tagId = result.url ?? result.id
      onSuccess(tagId)
    }
    nfcScanner.onError = onFailure

    nfcScanner.scan(profileName: "")
  }
}
