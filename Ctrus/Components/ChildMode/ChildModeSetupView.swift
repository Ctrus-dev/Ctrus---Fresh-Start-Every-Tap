import SwiftUI

/// Child mode setup, laid out like the guided profile creation: the parent
/// code (typed twice), the parents' Ctrus (at least one), then the recovery key,
/// shown once.
struct ChildModeSetupView: View {
  @EnvironmentObject private var themeManager: ThemeManager

  var onCancel: (() -> Void)? = nil
  let onFinished: () -> Void

  private enum Step: Int, CaseIterable {
    case code
    case confirmCode
    case parentTags
    case recoveryKey
  }

  static let recoveryKeyConfirmDelay: TimeInterval = 5

  @State private var step: Step = .code
  @State private var code = ""
  @State private var confirmedCode = ""
  @State private var parentTags: [ParentTag] = []
  @State private var recoveryKey = ""
  @State private var canConfirmRecoveryKey = false
  @State private var message: String? = nil
  @State private var tagReader = TagReader()

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            stepHeader
            stepCard

            if let message {
              Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
            }
          }
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))

        primaryButton
          .padding(.horizontal, 20)
          .padding(.top, 12)
          .padding(.bottom, 16)
      }
      .background(Color(.systemGroupedBackground).ignoresSafeArea())
      .toolbar {
        if step != .code || onCancel != nil {
          ToolbarItem(placement: .topBarLeading) {
            Button(action: goBack) {
              Label("Back", systemImage: "chevron.left")
            }
          }
        }
      }
    }
    .interactiveDismissDisabled()
  }

  // MARK: - Header

  private var stepHeader: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Step \(step.rawValue + 1) of \(Step.allCases.count)")
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.primary)
        .padding(.leading, 1)

      Text(stepTitle)
        .font(.largeTitle)
        .fontWeight(.bold)
        .foregroundStyle(.primary)

      Text(stepDescription)
        .font(.body)
        .foregroundStyle(.secondary)
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 20)
    .padding(.top, 20)
    .padding(.bottom, 28)
  }

  private var stepTitle: String {
    switch step {
    case .code: return String(localized: "Choose a 6-digit parent code")
    case .confirmCode: return String(localized: "Enter the code again")
    case .parentTags: return String(localized: "Parents' Ctrus")
    case .recoveryKey: return String(localized: "Your recovery key")
    }
  }

  private var stepDescription: String {
    switch step {
    case .code:
      return String(
        localized: "It confirms changes and ends sessions when the parents' Ctrus isn't at hand.")
    case .confirmCode:
      return String(localized: "Type the same code to make sure it's right.")
    case .parentTags:
      return String(
        localized: "The parents' Ctrus ends any session, on every profile.")
    case .recoveryKey:
      return String(
        localized:
          "If you lose your Ctrus and forget the code, this key is the only way back. Take a photo or write it down. It won't be shown again."
      )
    }
  }

  // MARK: - Content

  private var stepCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      stepContent
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 20)
    .padding(.vertical, 18)
    .background(Color(.secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    .padding(.horizontal, 20)
    .padding(.bottom, 20)
  }

  @ViewBuilder
  private var stepContent: some View {
    switch step {
    case .code:
      ParentCodeField(code: $code) { _ in goNext() }
        .id(Step.code)

    case .confirmCode:
      ParentCodeField(code: $code) { _ in goNext() }
        .id(Step.confirmCode)

    case .parentTags:
      VStack(spacing: 10) {
        ForEach(parentTags) { tag in
          parentTagRow(tag)
        }

        addTagButton
      }

    case .recoveryKey:
      Text(ParentCredentials.formattedRecoveryKey(recoveryKey))
        .font(.system(.title, design: .monospaced))
        .fontWeight(.semibold)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
  }

  private func parentTagRow(_ tag: ParentTag) -> some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(tag.label)
          .font(.subheadline)
          .foregroundStyle(.primary)
          .lineLimit(1)

        Text(tag.uid.uppercased())
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 8)

      Menu {
        Button(role: .destructive) {
          removeTag(tag)
        } label: {
          Label("Delete", systemImage: "trash")
        }
      } label: {
        Image(systemName: "ellipsis.circle")
          .font(.title3)
          .foregroundStyle(themeManager.themeColor)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity)
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(.thinMaterial)
        .overlay(
          RoundedRectangle(cornerRadius: 16)
            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
        )
    )
  }

  private var addTagButton: some View {
    Button(action: scanParentTag) {
      HStack(spacing: 8) {
        Image(systemName: "plus")
          .font(.system(size: 16, weight: .medium))
        Text(
          parentTags.isEmpty
            ? String(localized: "Tap the parents' Ctrus")
            : String(localized: "Add another parents' Ctrus")
        )
        .fontWeight(.semibold)
        .font(.subheadline)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
      .background(
        RoundedRectangle(cornerRadius: 16)
          .fill(.thinMaterial)
          .overlay(
            RoundedRectangle(cornerRadius: 16)
              .stroke(Color.primary.opacity(0.2), lineWidth: 1)
          )
      )
    }
    .buttonStyle(.plain)
  }

  // MARK: - Primary button

  private var primaryButton: some View {
    ActionButton(
      title: step == .recoveryKey ? String(localized: "I've saved it") : String(localized: "Next"),
      backgroundColor: themeManager.themeColor,
      isDisabled: !canContinue
    ) {
      goNext()
    }
  }

  private var canContinue: Bool {
    switch step {
    case .code, .confirmCode: return code.count == ParentCredentials.codeLength
    case .parentTags: return !parentTags.isEmpty
    case .recoveryKey: return canConfirmRecoveryKey
    }
  }

  // MARK: - Navigation

  private func goNext() {
    switch step {
    case .code:
      guard !ParentCredentials.isWeakCode(code) else {
        message = String(localized: "That code is too easy to guess.")
        code = ""
        return
      }
      message = nil
      confirmedCode = code
      code = ""
      step = .confirmCode

    case .confirmCode:
      guard code == confirmedCode else {
        message = String(localized: "The codes don't match.")
        code = ""
        confirmedCode = ""
        step = .code
        return
      }
      message = nil
      ParentCredentials.setParentCode(code)
      code = ""
      step = .parentTags

    case .parentTags:
      guard !parentTags.isEmpty else { return }
      message = nil
      recoveryKey = ParentCredentials.makeRecoveryKey()
      step = .recoveryKey
      startRecoveryKeyDelay()

    case .recoveryKey:
      finish()
    }
  }

  private func goBack() {
    message = nil

    switch step {
    case .code:
      onCancel?()
    case .confirmCode:
      code = ""
      confirmedCode = ""
      step = .code
    case .parentTags:
      // The code is typed again rather than kept half-confirmed.
      code = ""
      confirmedCode = ""
      step = .code
    case .recoveryKey:
      // A new key is made on the way forward again, so this one is useless.
      recoveryKey = ""
      step = .parentTags
    }
  }

  // MARK: - Actions

  private func scanParentTag() {
    tagReader.read(prompt: String(localized: "Tap the parents' Ctrus")) { result in
      let uid = ChildModeStore.normalizedUID(result.id)
      guard !parentTags.contains(where: { $0.uid == uid }) else { return }

      message = nil
      parentTags.append(ParentTag(uid: uid, url: result.url, label: nextLabel()))
    }
  }

  private func removeTag(_ tag: ParentTag) {
    parentTags.removeAll { $0.uid == tag.uid }
  }

  private func nextLabel() -> String {
    let used = Set(parentTags.map(\.label))
    let number =
      (1...(parentTags.count + 1)).first {
        !used.contains(String(localized: "Parents' Ctrus \($0)"))
      } ?? parentTags.count + 1
    return String(localized: "Parents' Ctrus \(number)")
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
