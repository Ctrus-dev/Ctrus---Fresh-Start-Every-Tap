import SwiftUI

/// Child mode setup, in order: the parent code, the parents' Ctrus (1 to 3),
/// then the recovery key, shown once.
struct ChildModeSetupView: View {
  @EnvironmentObject private var themeManager: ThemeManager

  var onCancel: (() -> Void)? = nil
  let onFinished: () -> Void

  private enum Step {
    case code
    case confirmCode
    case parentTags
    case recoveryKey
  }

  static let recoveryKeyConfirmDelay: TimeInterval = 5

  @State private var step: Step = .code
  @State private var code = ""
  @State private var firstCode = ""
  @State private var parentTags: [ParentTag] = []
  @State private var recoveryKey = ""
  @State private var canConfirmRecoveryKey = false
  @State private var message: String? = nil
  @State private var tagReader = TagReader()

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          stepContent

          if let message {
            Text(message)
              .font(.footnote)
              .foregroundStyle(.red)
              .frame(maxWidth: .infinity, alignment: .center)
          }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
      }
      .navigationTitle(String(localized: "Child mode"))
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        if let onCancel {
          ToolbarItem(placement: .topBarLeading) {
            Button(action: onCancel) {
              Image(systemName: "xmark")
            }
            .accessibilityLabel("Close")
          }
        }
      }
    }
    .interactiveDismissDisabled()
  }

  @ViewBuilder
  private var stepContent: some View {
    switch step {
    case .code:
      stepHeader(String(localized: "Choose a 6-digit parent code"))

      ParentCodeField(code: $code) { entered in
        guard !ParentCredentials.isWeakCode(entered) else {
          message = String(localized: "That code is too easy to guess.")
          code = ""
          return
        }
        message = nil
        firstCode = entered
        code = ""
        step = .confirmCode
      }
      .id("code")

    case .confirmCode:
      stepHeader(String(localized: "Enter the code again"))

      ParentCodeField(code: $code) { entered in
        guard entered == firstCode else {
          message = String(localized: "The codes don't match.")
          code = ""
          firstCode = ""
          step = .code
          return
        }
        message = nil
        ParentCredentials.setParentCode(entered)
        step = .parentTags
      }
      .id("confirmCode")

    case .parentTags:
      stepHeader(String(localized: "Tap the parents' Ctrus"))

      VStack(spacing: 12) {
        ForEach(parentTags) { tag in
          HStack {
            Image(systemName: "wave.3.right")
              .foregroundStyle(themeManager.themeColor)
            Text(tag.label)
            Spacer()
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(themeManager.themeColor)
          }
          .padding(14)
          .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }

        if parentTags.count < ChildModeStore.maxParentTags {
          ActionButton(
            title: parentTags.isEmpty
              ? String(localized: "Tap the parents' Ctrus")
              : String(localized: "Add another parents' Ctrus"),
            backgroundColor: parentTags.isEmpty ? themeManager.themeColor : .gray,
            iconName: "wave.3.right"
          ) {
            scanParentTag()
          }
        }

        if !parentTags.isEmpty {
          ActionButton(
            title: String(localized: "Continue"),
            backgroundColor: themeManager.themeColor
          ) {
            recoveryKey = ParentCredentials.makeRecoveryKey()
            step = .recoveryKey
            startRecoveryKeyDelay()
          }
        }
      }

    case .recoveryKey:
      stepHeader(String(localized: "Your recovery key"))

      Text(
        "If you lose your Ctrus and forget the code, this key is the only way back. Take a photo or write it down. It won't be shown again."
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      Text(ParentCredentials.formattedRecoveryKey(recoveryKey))
        .font(.system(.title, design: .monospaced))
        .fontWeight(.semibold)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

      ActionButton(
        title: String(localized: "I've saved it"),
        backgroundColor: themeManager.themeColor,
        isDisabled: !canConfirmRecoveryKey
      ) {
        finish()
      }
    }
  }

  private func stepHeader(_ title: String) -> some View {
    Text(title)
      .font(.title3)
      .fontWeight(.semibold)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func scanParentTag() {
    tagReader.read(prompt: String(localized: "Tap the parents' Ctrus")) { result in
      let uid = ChildModeStore.normalizedUID(result.id)
      guard !parentTags.contains(where: { $0.uid == uid }) else { return }

      message = nil
      parentTags.append(
        ParentTag(
          uid: uid,
          url: result.url,
          label: String(localized: "Parents' Ctrus \(parentTags.count + 1)")
        )
      )
    }
  }

  private func startRecoveryKeyDelay() {
    canConfirmRecoveryKey = false
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.recoveryKeyConfirmDelay) {
      canConfirmRecoveryKey = true
    }
  }

  private func finish() {
    ChildModeStore.parentTags = parentTags
    ChildModeStore.appMode = .child
    onFinished()
  }
}

#Preview {
  ChildModeSetupView(onFinished: {})
    .environmentObject(ThemeManager.shared)
}
