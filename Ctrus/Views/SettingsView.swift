import FamilyControls
import SwiftData
import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @EnvironmentObject var themeManager: ThemeManager
  @EnvironmentObject var requestAuthorizer: RequestAuthorizer
  @EnvironmentObject var strategyManager: StrategyManager

  @State private var showResetBlockingStateAlert = false
  @State private var showDebugView = false
  @State private var unlockCode = ""
  @State private var isVerifyingUnlockCode = false
  @State private var showInvalidUnlockCodeAlert = false
  @State private var showUnlockNetworkErrorAlert = false
  @State private var showDeviceIDCopiedConfirmation = false

  private var appVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
      ?? "1.0"
  }

  private var recoveryUnlocksRemaining: Int {
    strategyManager.getRemainingRecoveryUnlocks()
  }

  private var hasRecoveryUnlockRemaining: Bool {
    recoveryUnlocksRemaining > 0
  }

  private var isRecoveryUnlockLow: Bool {
    recoveryUnlocksRemaining <= 1
  }

  private var recoveryUnlockStatusText: Text {
    if recoveryUnlocksRemaining == 1 {
      return Text("You only have 1 unlock left.")
    }

    guard let nextResetDate = strategyManager.getNextRecoveryResetDate() else {
      return Text("You have access to 2 unlocks every 4 weeks.")
    }

    let timeUntilReset = nextResetDate.timeIntervalSinceNow
    if timeUntilReset <= 24 * 60 * 60 {
      let hoursRemaining = max(1, Int(ceil(timeUntilReset / 3600)))
      return Text("No unlocks remaining. Resets in \(hoursRemaining)h.")
    } else {
      return Text(
        "No unlocks remaining. Resets \(nextResetDate, format: .dateTime.month().day())."
      )
    }
  }

  @ViewBuilder
  private var recoverySectionContent: some View {
    Link(destination: URL(string: "https://recover.ctrus.net")!) {
      HStack {
        Text("Get an Unlock Code")
          .foregroundColor(.primary)
        Spacer()
        Image(systemName: "arrow.up.right.square")
          .foregroundColor(.secondary)
      }
    }

    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text("Device ID")
          .foregroundColor(.primary)
        Text(RecoveryCodeUtil.deviceID)
          .font(.caption)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }

      Spacer()

      Button {
        UIPasteboard.general.string = RecoveryCodeUtil.deviceID
        showDeviceIDCopiedConfirmation = true
      } label: {
        Image(systemName: "doc.on.doc")
      }
      .foregroundColor(themeManager.themeColor)
    }

    HStack {
      TextField("Enter code", text: $unlockCode)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .disabled(isVerifyingUnlockCode || !hasRecoveryUnlockRemaining)

      if isVerifyingUnlockCode {
        ProgressView()
      } else {
        Button("Unlock") {
          submitUnlockCode()
        }
        .disabled(unlockCode.isEmpty || !hasRecoveryUnlockRemaining)
        .foregroundColor(themeManager.themeColor)
      }
    }
    .listRowSeparator(.visible)
    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }

    HStack(spacing: 6) {
      Image(systemName: "clock.arrow.circlepath")
        .font(.caption2)
        .foregroundStyle(.secondary)

      recoveryUnlockStatusText
        .font(.caption)
        .foregroundStyle(isRecoveryUnlockLow ? Color.red : Color.secondary)
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Theme") {
          HStack {
            Image(systemName: "paintpalette.fill")
              .foregroundStyle(themeManager.themeColor)
              .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
              Text("Appearance")
                .font(.headline)
              Text("Customize the look of your app")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          .padding(.vertical, 8)
          .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }

          Picker("Theme Color", selection: $themeManager.selectedColorName) {
            ForEach(ThemeManager.availableColors, id: \.name) { colorOption in
              HStack {
                Circle()
                  .fill(colorOption.color)
                  .frame(width: 20, height: 20)
                Text(LocalizedStringKey(colorOption.name))
              }
              .tag(colorOption.name)
            }
          }
          .onChange(of: themeManager.selectedColorName) { _, _ in
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
          }
        }

        AppIconPicker(selectionColor: themeManager.themeColor)

        Section("Help") {
          HStack {
            Text("Debug Mode")
              .foregroundColor(.primary)
            Spacer()
            Image(systemName: "chevron.right")
              .foregroundColor(.secondary)
              .font(.caption)
          }
          .onTapGesture {
            showDebugView = true
          }

          if !strategyManager.isBlocking {
            Button {
              showResetBlockingStateAlert = true
            } label: {
              Text("Reset Blocking State")
                .foregroundColor(themeManager.themeColor)
            }
          }
        }

        Section("Locked Out and Lost Your Ctrus?") {
          recoverySectionContent
        }

        Section("About") {
          HStack {
            Text("Version")
              .foregroundStyle(.primary)
            Spacer()
            Text("v\(appVersion)")
              .foregroundStyle(.secondary)
          }

          HStack {
            Text("Screen Time Access")
              .foregroundStyle(.primary)
            Spacer()
            HStack(spacing: 8) {
              Circle()
                .fill(requestAuthorizer.getAuthorizationStatus() == .approved ? .green : .red)
                .frame(width: 8, height: 8)
              Text(
                requestAuthorizer.getAuthorizationStatus() == .approved
                  ? "Authorized" : "Not Authorized"
              )
              .foregroundStyle(.secondary)
              .font(.subheadline)
            }
          }

          HStack {
            Text("Made in")
              .foregroundStyle(.primary)
            Spacer()
            Text("🇵🇹")
              .foregroundStyle(.secondary)
          }

          Link(destination: URL(string: "https://www.foqos.app")!) {
            HStack {
              Text("Based on Foqos - Tap to Block")
                .foregroundColor(.primary)
              Spacer()
              Image(systemName: "arrow.up.right.square")
                .foregroundColor(.secondary)
            }
          }
        }

      }
      .navigationTitle("Settings")
      .onAppear {
        strategyManager.checkAndResetRecoveryUnlocks()
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: { dismiss() }) {
            Image(systemName: "xmark")
          }
          .accessibilityLabel("Close")
        }
      }
      .alert("Reset Blocking State", isPresented: $showResetBlockingStateAlert) {
        Button("Cancel", role: .cancel) {}
        Button("Reset", role: .destructive) {
          strategyManager.resetBlockingState(context: context)
        }
      } message: {
        Text(
          "This will clear all app restrictions and remove any ghost schedules. Only use this if you're locked out and no profile is active."
        )
      }
      .sheet(isPresented: $showDebugView) {
        DebugView()
      }
      .alert("Invalid Code", isPresented: $showInvalidUnlockCodeAlert) {
        Button("OK", role: .cancel) {}
      } message: {
        Text("That unlock code isn't valid or has expired. Visit recover.ctrus.net to get a new one.")
      }
      .alert("Connection Problem", isPresented: $showUnlockNetworkErrorAlert) {
        Button("OK", role: .cancel) {}
      } message: {
        Text("Couldn't reach the server to check your code. Check your connection and try again.")
      }
      .alert("Copied to Clipboard", isPresented: $showDeviceIDCopiedConfirmation) {
        Button("OK", role: .cancel) {}
      } message: {
        Text("Your Device ID has been copied.")
      }
    }
  }

  private func submitUnlockCode() {
    isVerifyingUnlockCode = true

    Task {
      let result = await strategyManager.unlockWithRecoveryCode(unlockCode, context: context)
      isVerifyingUnlockCode = false

      switch result {
      case .valid:
        unlockCode = ""
      case .invalid:
        showInvalidUnlockCodeAlert = true
      case .networkError:
        showUnlockNetworkErrorAlert = true
      }
    }
  }
}

#Preview {
  SettingsView()
    .environmentObject(ThemeManager.shared)
    .environmentObject(RequestAuthorizer())
    .environmentObject(StrategyManager.shared)
    .modelContainer(for: BlockedProfiles.self, inMemory: true)
}
