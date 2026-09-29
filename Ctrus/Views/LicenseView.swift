import SwiftUI

struct LicenseView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text("MIT License")
            .font(.headline)
            .foregroundStyle(.primary)

          // Verbatim: copyright names/dates are never translated, and this
          // keeps them out of the string catalog instead of leaving an
          // untranslated stub entry behind.
          Text(verbatim: "Copyright (c) 2024 Ali Waseem")

          Text(verbatim: "Copyright (c) 2026 Martim Oliveira")

          Text(permissionGrantText)

          Text(copyrightNoticeText)

          Text(warrantyDisclaimerText)

          if let translationDisclaimerText {
            Text(translationDisclaimerText)
              .font(.caption)
              .italic()
              .padding(.top, 4)
          }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding()
      }
      .navigationTitle("License")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: { dismiss() }) {
            Image(systemName: "xmark")
          }
          .accessibilityLabel("Close")
        }
      }
    }
  }

  private var permissionGrantText: String {
    String(
      localized:
        "Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:"
    )
  }

  private var copyrightNoticeText: String {
    String(
      localized:
        "The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software."
    )
  }

  private var warrantyDisclaimerText: String {
    String(
      localized:
        "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE."
    )
  }

  // The license itself is only ever legally the English original — this note
  // only makes sense to show alongside a translated copy, so it's gated to
  // the languages Ctrus actually translates into.
  private var translationDisclaimerText: String? {
    guard let languageCode = Locale.current.language.languageCode?.identifier,
      ["pt", "es"].contains(languageCode)
    else {
      return nil
    }

    return String(
      localized:
        "Translation for reference only. In case of any discrepancy, the original English text prevails."
    )
  }
}

#Preview {
  LicenseView()
}
