import SwiftUI

/// A request for the parents to confirm one action. The confirmation covers
/// only that action — nothing stays unlocked afterwards.
struct ParentConfirmationRequest: Identifiable {
  let id = UUID()
  let reason: String
  let action: () -> Void
}

/// The single parent confirmation screen: the parents' Ctrus, the parent
/// code, or — if the code is forgotten — the recovery key and a new code.
struct ParentConfirmationView: View {
  @EnvironmentObject private var themeManager: ThemeManager
  @Environment(\.dismiss) private var dismiss

  let reason: String
  let onConfirmed: () -> Void

  private enum Step {
    case code
    case recoveryKey
    case newCode
    case confirmNewCode
  }

  @State private var step: Step = .code
  @State private var code = ""
  @State private var recoveryKey = ""
  @State private var newCode = ""
  @State private var message: String? = nil
  @State private var lockRemaining: TimeInterval = 0
  @State private var tagReader = TagReader()

  private let lockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 24) {
          Text(reason)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

          ActionButton(
            title: String(localized: "Use the parents' Ctrus"),
            backgroundColor: themeManager.themeColor,
            iconName: "wave.3.right"
          ) {
            scanParentTag()
          }

          Divider()

          stepContent

          if let message {
            Text(message)
              .font(.footnote)
              .foregroundStyle(.red)
              .multilineTextAlignment(.center)
              .frame(maxWidth: .infinity)
          }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
      }
      .navigationTitle(stepTitle)
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: { dismiss() }) {
            Image(systemName: "xmark")
          }
          .accessibilityLabel("Close")
        }
      }
    }
    // Links and toolbar buttons in the theme colour, not the system blue.
    .tint(themeManager.themeColor)
    .onAppear(perform: refreshLock)
    .onReceive(lockTimer) { _ in
      if lockRemaining > 0 { refreshLock() }
    }
  }

  private var stepTitle: String {
    switch step {
    case .code: return String(localized: "Parent code")
    case .recoveryKey: return String(localized: "Enter the recovery key")
    case .newCode, .confirmNewCode: return String(localized: "Choose a 6-digit parent code")
    }
  }

  @ViewBuilder
  private var stepContent: some View {
    switch step {
    case .code:
      VStack(spacing: 16) {
        ParentCodeField(code: $code, isDisabled: lockRemaining > 0) { entered in
          checkCode(entered)
        }

        if lockRemaining > 0 {
          lockText
        }

        Button(String(localized: "I forgot the code")) {
          message = nil
          step = .recoveryKey
          refreshLock()
        }
        .font(.subheadline)
      }

    case .recoveryKey:
      VStack(spacing: 16) {
        TextField("XXXX-XXXX-XXXX", text: $recoveryKey)
          .textInputAutocapitalization(.characters)
          .autocorrectionDisabled()
          .font(.system(.title3, design: .monospaced))
          .multilineTextAlignment(.center)
          .padding(12)
          .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
          .disabled(lockRemaining > 0)

        if lockRemaining > 0 {
          lockText
        }

        ActionButton(
          title: String(localized: "Continue"),
          backgroundColor: themeManager.themeColor,
          isDisabled: lockRemaining > 0
            || ParentCredentials.normalizedRecoveryKey(recoveryKey).count
              != ParentCredentials.recoveryKeyLength
        ) {
          checkRecoveryKey()
        }
      }

    case .newCode:
      ParentCodeField(code: $newCode) { entered in
        guard !ParentCredentials.isWeakCode(entered) else {
          message = String(localized: "That code is too easy to guess.")
          newCode = ""
          return
        }
        message = nil
        code = ""
        step = .confirmNewCode
      }
      .id("newCode")

    case .confirmNewCode:
      VStack(spacing: 12) {
        Text("Enter the code again")
          .font(.subheadline)
          .foregroundStyle(.secondary)

        ParentCodeField(code: $code) { entered in
          guard entered == newCode else {
            message = String(localized: "The codes don't match.")
            code = ""
            newCode = ""
            step = .newCode
            return
          }
          ParentCredentials.setParentCode(entered)
          confirm()
        }
        .id("confirmNewCode")
      }
    }
  }

  private var lockText: some View {
    Text(
      String(
        localized: "Too many attempts. Try again in \(Self.formattedWait(lockRemaining))."))
      .font(.footnote)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
  }

  // MARK: - Actions

  private func scanParentTag() {
    tagReader.read(prompt: String(localized: "Tap the parents' Ctrus")) { result in
      guard ChildModeStore.isParentTag(uid: result.id) else {
        message = String(localized: "This isn't a parents' Ctrus.")
        return
      }
      ParentCredentials.resetAttempts(for: .parentCode)
      ParentCredentials.resetAttempts(for: .recoveryKey)
      confirm()
    }
  }

  private func checkCode(_ entered: String) {
    switch ParentCredentials.verify(entered, against: .parentCode) {
    case .valid:
      confirm()
    case .invalid:
      message = String(localized: "That code isn't right.")
      code = ""
    case .locked:
      message = nil
      code = ""
      refreshLock()
    }
  }

  private func checkRecoveryKey() {
    switch ParentCredentials.verify(recoveryKey, against: .recoveryKey) {
    case .valid:
      message = nil
      newCode = ""
      step = .newCode
    case .invalid:
      message = String(localized: "That recovery key isn't right.")
    case .locked:
      message = nil
      refreshLock()
    }
  }

  private func refreshLock() {
    let secret: ParentCredentials.Secret = step == .recoveryKey ? .recoveryKey : .parentCode
    lockRemaining = ParentCredentials.lockRemaining(for: secret)
  }

  private func confirm() {
    onConfirmed()
    dismiss()
  }

  static func formattedWait(_ seconds: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
    formatter.unitsStyle = .abbreviated
    return formatter.string(from: max(1, seconds.rounded(.up))) ?? ""
  }
}

/// Reads one NFC tag and hands back what was read.
final class TagReader {
  private let scanner = NFCScannerUtil()

  func read(prompt: String, onRead: @escaping (NFCResult) -> Void) {
    scanner.onTagScanned = onRead
    scanner.scan(alertMessage: prompt)
  }
}

extension View {
  /// Shows the parent confirmation for `request`, and runs its action only
  /// after the screen has closed, so the action can present screens of its own.
  func parentConfirmation(_ request: Binding<ParentConfirmationRequest?>) -> some View {
    modifier(ParentConfirmationPresenter(request: request))
  }
}

private struct ParentConfirmationPresenter: ViewModifier {
  @Binding var request: ParentConfirmationRequest?
  @State private var confirmedAction: (() -> Void)? = nil

  func body(content: Content) -> some View {
    content
      .sheet(
        item: $request,
        onDismiss: {
          confirmedAction?()
          confirmedAction = nil
        }
      ) { request in
        ParentConfirmationView(reason: request.reason) {
          confirmedAction = request.action
        }
        .presentationDetents([.large])
      }
  }
}

#Preview {
  ParentConfirmationView(reason: "To edit this profile", onConfirmed: {})
    .environmentObject(ThemeManager.shared)
}
