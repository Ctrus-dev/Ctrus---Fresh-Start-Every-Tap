import FamilyControls
import SwiftData
import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @EnvironmentObject var themeManager: ThemeManager
  @EnvironmentObject var requestAuthorizer: RequestAuthorizer
  @EnvironmentObject var strategyManager: StrategyManager

  @State private var showLicenseView = false
  @State private var unlockCode = ""
  @State private var isVerifyingUnlockCode = false
  @State private var showInvalidUnlockCodeAlert = false
  @State private var showUnlockNetworkErrorAlert = false
  @State private var showDeviceIDCopiedConfirmation = false
  @State private var showLastRecoveryCodeWarning = false

  @AppStorage("useLeftHandedLayout") private var useLeftHandedLayout = false

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
    guard let nextResetDate = strategyManager.getNextRecoveryResetDate() else {
      return Text("You have access to 2 unlocks every 4 weeks.")
    }

    let timeUntilReset = nextResetDate.timeIntervalSinceNow

    if recoveryUnlocksRemaining == 1 {
      if timeUntilReset <= 24 * 60 * 60 {
        let hoursRemaining = max(1, Int(ceil(timeUntilReset / 3600)))
        return Text("You only have 1 unlock left. Resets in \(hoursRemaining)h.")
      } else {
        return Text(
          "You only have 1 unlock left. Resets \(nextResetDate, format: .dateTime.month().day())."
        )
      }
    }

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
    Link(destination: URL(string: "https://recover.ctrus.pt")!) {
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
          Link(destination: URL(string: "https://ctrus.pt/pages/faq")!) {
            HStack {
              Text("Looking for Answers?")
                .foregroundColor(.primary)
              Spacer()
              Image(systemName: "arrow.up.right.square")
                .foregroundColor(.secondary)
            }
          }
        }

        Section("Locked Out and Lost Your Ctrus?") {
          recoverySectionContent
        }

        Section("Accessibility") {
          Toggle(isOn: $useLeftHandedLayout) {
            VStack(alignment: .leading, spacing: 2) {
              Text("Left-Handed Layout")
              Text("Moves the profile and settings buttons to the left")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
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
            Text("License")
              .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
              .foregroundColor(.secondary)
              .font(.caption)
          }
          .contentShape(Rectangle())
          .onTapGesture {
            showLicenseView = true
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
        }

        // Outside every section, so it sits in the normal scroll flow right
        // after About instead of floating over whatever section is on
        // screen while scrolling.
        (Text("Ctrus is 100% open source, ")
          + Text("read the code yourself")
          .foregroundColor(themeManager.themeColor))
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
          .onTapGesture {
            if let url = URL(
              string: "https://github.com/Ctrus-dev/Ctrus---Fresh-Start-Every-Tap")
            {
              UIApplication.shared.open(url)
            }
          }
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)

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
      .sheet(isPresented: $showLicenseView) {
        LicenseView()
      }
      .alert("Invalid Code", isPresented: $showInvalidUnlockCodeAlert) {
        Button("OK", role: .cancel) {}
      } message: {
        Text("That unlock code isn't valid or has expired. Visit recover.ctrus.pt to get a new one.")
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
      .alert("Warning!", isPresented: $showLastRecoveryCodeWarning) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(
          "You've used up all your emergency unblocks, and you only have one more unlock code left until it resets. We'd recommend not blocking apps you might urgently need."
        )
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
        if strategyManager.getRemainingEmergencyUnblocks() == 0
          && strategyManager.getRemainingRecoveryUnlocks() == 1
        {
          showLastRecoveryCodeWarning = true
        }
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
