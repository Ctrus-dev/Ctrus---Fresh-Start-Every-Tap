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
            themedLabel("Change parent code", systemImage: "lock.rotation")
          }

          NavigationLink(value: Destination.parentTags) {
            themedLabel("Parents' Ctrus", systemImage: "wave.3.right")
          }

          NavigationLink(value: Destination.newRecoveryKey) {
            themedLabel("Create a new recovery key", systemImage: "key")
          }

          NavigationLink(value: Destination.log) {
            themedLabel("Attempt log", systemImage: "list.bullet.rectangle")
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
          "The parent code, recovery key and attempt log are deleted. Your profiles stay, and can still be unblocked with the Ctrus they used in Child Mode."
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

extension ChildModeSettingsView {
  // Only the row icons take the theme colour; the toolbar keeps the system
  // look, like Settings.
  fileprivate func themedLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
    Label {
      Text(title)
    } icon: {
      Image(systemName: systemImage)
        .foregroundStyle(themeManager.themeColor)
    }
  }
}

/// Leaving child mode: everything that belongs only to it goes; the
/// profiles stay, and keep every Ctrus they were linked to (the parents', and
/// their own child's) as physical unlocks, so they can still be ended in
/// normal mode.
enum ChildModeSwitcher {
  static func switchToNormal(in context: ModelContext) {
    let parentTags = ChildModeStore.parentTags

    ChildSessionLimit.end()
    ParentCredentials.clearAll()
    ChildModeStore.clearChildModeData()

    if let profiles = try? BlockedProfiles.fetchProfiles(in: context) {
      for profile in profiles {
        profile.physicalUnblockItems = PhysicalUnblockItem.normalizedItems(
          physicalUnblocks(for: profile, adding: parentTags))
        profile.childTag = nil
        profile.childTagCanStop = false
        BlockedProfiles.updateSnapshot(for: profile)
      }
      try? context.save()
    }
  }

  /// The profile's own unlocks plus each linked Ctrus it doesn't have yet,
  /// stored the way normal mode reads a scanned tag (its URL, else its ID).
  private static func physicalUnblocks(
    for profile: BlockedProfiles,
    adding parentTags: [ParentTag]
  ) -> [PhysicalUnblockItem] {
    var items = profile.physicalUnblockItems ?? []

    var linkedTags = parentTags.map { (uid: $0.uid, url: $0.url) }
    if let childTag = profile.childTag {
      linkedTags.append((uid: childTag.uid, url: childTag.url))
    }

    for tag in linkedTags {
      let codeValue = tag.url ?? tag.uid.uppercased()
      let alreadyThere = items.contains {
        $0.type == .nfc
          && ($0.codeValue == codeValue
            || ChildModeStore.normalizedUID($0.codeValue) == ChildModeStore.normalizedUID(tag.uid))
      }
      guard !alreadyThere else { continue }

      let number = items.filter { $0.type == .nfc }.count + 1
      items.append(
        PhysicalUnblockItem(
          name: String(localized: "Ctrus \(number)"),
          type: .nfc,
          codeValue: codeValue
        )
      )
    }

    return items
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
          HStack {
            Label {
              Text(tag.label)
            } icon: {
              Image(systemName: "wave.3.right")
                .foregroundStyle(themeManager.themeColor)
            }

            Spacer()

            // There always has to be at least one.
            if parentTags.count > 1 {
              Button {
                removeTag(tag)
              } label: {
                Image(systemName: "trash")
                  .foregroundStyle(.red)
              }
              .buttonStyle(.borderless)
              .accessibilityLabel("Delete")
            }
          }
        }
      } footer: {
        Text("Changes apply to every profile straight away.")
      }

      Section {
        Button {
          addTag()
        } label: {
          Label("Add another parents' Ctrus", systemImage: "plus")
        }
        .foregroundStyle(themeManager.themeColor)
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
      let number = (1...(parentTags.count + 1)).first {
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

  private func removeTag(_ tag: ParentTag) {
    guard parentTags.count > 1 else { return }
    parentTags.removeAll { $0.uid == tag.uid }
    save()
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
  @EnvironmentObject private var themeManager: ThemeManager

  @State private var entries = Array(ChildModeStore.tamperLog.reversed())
  @State private var showClearAlert = false

  var body: some View {
    List {
      if entries.isEmpty {
        Text("Nothing recorded yet.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(entries) { entry in
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
    .toolbar {
      if !entries.isEmpty {
        ToolbarItem(placement: .topBarTrailing) {
          Button(String(localized: "Clear")) {
            showClearAlert = true
          }
          .tint(themeManager.themeColor)
        }
      }
    }
    .alert(String(localized: "Clear the attempt log?"), isPresented: $showClearAlert) {
      Button(String(localized: "Clear"), role: .destructive) {
        ChildModeStore.tamperLog = []
        ChildModeStore.tamperLogUnseen = false
        entries = []
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Every entry is deleted. This can't be undone.")
    }
    .onAppear {
      ChildModeStore.tamperLogUnseen = false
    }
  }
}
