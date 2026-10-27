import SwiftData
import SwiftUI

/// Settings > Child mode, reached only after the parents confirm.
struct ChildModeSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @EnvironmentObject private var themeManager: ThemeManager

  var startsOnLog = false
  let onSwitchedToNormal: () -> Void

  @State private var showSwitchToNormalAlert = false
  @State private var path: [Destination] = []

  enum Destination: Hashable {
    case changeCode
    case parentTags
    case newRecoveryKey
    case log
  }

  var body: some View {
    NavigationStack(path: $path) {
      List {
        Section {
          NavigationLink(value: Destination.changeCode) {
            Label("Change parent code", systemImage: "lock.rotation")
          }

          NavigationLink(value: Destination.parentTags) {
            Label("Parents' Ctrus", systemImage: "wave.3.right")
          }

          NavigationLink(value: Destination.newRecoveryKey) {
            Label("Create a new recovery key", systemImage: "key")
          }

          NavigationLink(value: Destination.log) {
            Label("Attempt log", systemImage: "list.bullet.rectangle")
          }
        }

        Section {
          Button(role: .destructive) {
            showSwitchToNormalAlert = true
          } label: {
            Text("Switch to Normal Mode")
          }
        }
      }
      .navigationTitle(String(localized: "Child Mode"))
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: { dismiss() }) {
            Image(systemName: "xmark")
          }
          .accessibilityLabel("Close")
        }
      }
      .navigationDestination(for: Destination.self) { destination in
        switch destination {
        case .changeCode:
          ChangeParentCodeView {
            path.removeLast()
          }
        case .parentTags:
          ParentTagsView()
        case .newRecoveryKey:
          NewRecoveryKeyView {
            path.removeLast()
          }
        case .log:
          TamperLogView()
        }
      }
      .alert(
        String(localized: "Switch to Normal Mode"),
        isPresented: $showSwitchToNormalAlert
      ) {
        Button(String(localized: "Switch to Normal Mode"), role: .destructive) {
          ChildModeSwitcher.switchToNormal(in: context)
          dismiss()
          onSwitchedToNormal()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "The parent code, recovery key, parents' Ctrus and attempt log are deleted. Your profiles stay."
        )
      }
    }
    .onAppear {
      if startsOnLog {
        path = [.log]
      }
    }
  }
}

/// Leaving child mode: everything that belongs only to it goes; the
/// profiles stay.
enum ChildModeSwitcher {
  static func switchToNormal(in context: ModelContext) {
    ChildSessionLimit.end()
    ParentCredentials.clearAll()
    ChildModeStore.clearChildModeData()

    if let profiles = try? BlockedProfiles.fetchProfiles(in: context) {
      for profile in profiles {
        profile.childTag = nil
        profile.childTagCanStop = false
        BlockedProfiles.updateSnapshot(for: profile)
      }
      try? context.save()
    }
  }
}

// MARK: - Change code

private struct ChangeParentCodeView: View {
  let onDone: () -> Void

  @State private var code = ""
  @State private var firstCode = ""
  @State private var isConfirming = false
  @State private var message: String? = nil

  var body: some View {
    VStack(spacing: 24) {
      Text(
        isConfirming
          ? String(localized: "Enter the code again")
          : String(localized: "Choose a 6-digit parent code")
      )
      .font(.title3)
      .fontWeight(.semibold)
      .frame(maxWidth: .infinity, alignment: .leading)

      ParentCodeField(code: $code) { entered in
        if !isConfirming {
          guard !ParentCredentials.isWeakCode(entered) else {
            message = String(localized: "That code is too easy to guess.")
            code = ""
            return
          }
          message = nil
          firstCode = entered
          code = ""
          isConfirming = true
        } else {
          guard entered == firstCode else {
            message = String(localized: "The codes don't match.")
            code = ""
            firstCode = ""
            isConfirming = false
            return
          }
          ParentCredentials.setParentCode(entered)
          onDone()
        }
      }
      .id(isConfirming)

      if let message {
        Text(message)
          .font(.footnote)
          .foregroundStyle(.red)
      }

      Spacer()
    }
    .padding(24)
    .navigationTitle(String(localized: "Change parent code"))
    .navigationBarTitleDisplayMode(.inline)
  }
}

// MARK: - Parents' Ctrus

private struct ParentTagsView: View {
  @EnvironmentObject private var themeManager: ThemeManager

  @State private var parentTags = ChildModeStore.parentTags
  @State private var tagReader = TagReader()

  var body: some View {
    List {
      Section {
        ForEach(parentTags) { tag in
          Label(tag.label, systemImage: "wave.3.right")
            .deleteDisabled(parentTags.count <= 1)
        }
        .onDelete { offsets in
          // There always has to be at least one.
          guard parentTags.count - offsets.count >= 1 else { return }
          parentTags.remove(atOffsets: offsets)
          save()
        }
      } footer: {
        Text("Changes apply to every profile straight away.")
      }

      if parentTags.count < ChildModeStore.maxParentTags {
        Section {
          Button {
            addTag()
          } label: {
            Label("Add another parents' Ctrus", systemImage: "plus")
          }
          .foregroundStyle(themeManager.themeColor)
        }
      }
    }
    .navigationTitle(String(localized: "Parents' Ctrus"))
    .navigationBarTitleDisplayMode(.inline)
  }

  private func addTag() {
    tagReader.read(prompt: String(localized: "Tap the parents' Ctrus")) { result in
      let uid = ChildModeStore.normalizedUID(result.id)
      guard !parentTags.contains(where: { $0.uid == uid }) else { return }

      let usedNumbers = Set(parentTags.map(\.label))
      let number = (1...ChildModeStore.maxParentTags).first {
        !usedNumbers.contains(String(localized: "Parents' Ctrus \($0)"))
      } ?? parentTags.count + 1

      parentTags.append(
        ParentTag(
          uid: uid,
          url: result.url,
          label: String(localized: "Parents' Ctrus \(number)")
        )
      )
      save()
    }
  }

  private func save() {
    ChildModeStore.parentTags = parentTags
  }
}

// MARK: - New recovery key

private struct NewRecoveryKeyView: View {
  @EnvironmentObject private var themeManager: ThemeManager

  let onDone: () -> Void

  @State private var recoveryKey: String? = nil
  @State private var canConfirm = false

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      if let recoveryKey {
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
          isDisabled: !canConfirm
        ) {
          onDone()
        }
      } else {
        Text("The current recovery key stops working as soon as a new one is created.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        ActionButton(
          title: String(localized: "Create a new recovery key"),
          backgroundColor: themeManager.themeColor
        ) {
          recoveryKey = ParentCredentials.makeRecoveryKey()
          DispatchQueue.main.asyncAfter(
            deadline: .now() + ChildModeSetupView.recoveryKeyConfirmDelay
          ) {
            canConfirm = true
          }
        }
      }

      Spacer()
    }
    .padding(24)
    .navigationTitle(String(localized: "Your recovery key"))
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(recoveryKey != nil)
  }
}

// MARK: - Attempt log

struct TamperLogView: View {
  private let entries = ChildModeStore.tamperLog.reversed()

  var body: some View {
    List {
      if entries.isEmpty {
        Text("Nothing recorded yet.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(Array(entries)) { entry in
          VStack(alignment: .leading, spacing: 3) {
            Text(entry.title)
            Text(entry.at, format: .dateTime.day().month().year().hour().minute())
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .navigationTitle(String(localized: "Attempt log"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      ChildModeStore.tamperLogUnseen = false
    }
  }
}
