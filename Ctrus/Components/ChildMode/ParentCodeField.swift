import SwiftUI

/// Six dots that fill as the code is typed on the number pad.
struct ParentCodeField: View {
  @EnvironmentObject private var themeManager: ThemeManager

  @Binding var code: String
  var isDisabled: Bool = false
  let onComplete: (String) -> Void

  @FocusState private var isFocused: Bool

  var body: some View {
    ZStack {
      // The real input, kept invisible; the dots are what's seen.
      SecureField("", text: $code)
        .keyboardType(.numberPad)
        .textContentType(.oneTimeCode)
        .focused($isFocused)
        .opacity(0.01)
        .disabled(isDisabled)
        .onChange(of: code) { _, newValue in
          let digits = String(newValue.filter(\.isNumber).prefix(ParentCredentials.codeLength))
          if digits != newValue {
            code = digits
            return
          }
          if digits.count == ParentCredentials.codeLength {
            onComplete(digits)
          }
        }

      HStack(spacing: 16) {
        ForEach(0..<ParentCredentials.codeLength, id: \.self) { index in
          Circle()
            .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1.5)
            .background(
              Circle().fill(index < code.count ? themeManager.themeColor : Color.clear)
            )
            .frame(width: 18, height: 18)
        }
      }
      .opacity(isDisabled ? 0.4 : 1)
      .allowsHitTesting(false)
    }
    .frame(maxWidth: .infinity, minHeight: 44)
    .contentShape(Rectangle())
    .onTapGesture {
      isFocused = true
    }
    .onAppear {
      isFocused = !isDisabled
    }
    .accessibilityLabel(String(localized: "Parent code"))
  }
}

#Preview {
  ParentCodeField(code: .constant("123"), onComplete: { _ in })
    .environmentObject(ThemeManager.shared)
    .padding()
}
