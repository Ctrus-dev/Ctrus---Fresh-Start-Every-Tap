import FamilyControls
import Foundation
import SwiftData
import SwiftUI

// Alert identifier for managing multiple alerts
struct AlertIdentifier: Identifiable {
  enum AlertType {
    case error
    case deleteProfile
    case missingPhysicalUnlock
    case discardChanges
  }

  let id: AlertType
  var errorMessage: String?
}

struct BlockedProfileView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss

  @EnvironmentObject private var strategyManager: StrategyManager

  // If profile is nil, we're creating a new profile
  var profile: BlockedProfiles?

  @StateObject private var draft: BlockedProfileDraft

  // Sheet for activity picker
  @State private var showingActivityPicker = false

  // Sheet for domain picker
  @State private var showingDomainPicker = false

  // Alert management
  @State private var alertIdentifier: AlertIdentifier?

  // Alert for cloning
  @State private var showingClonePrompt = false
  @State private var cloneName: String = ""

  // Sheet for insights modal
  @State private var showingInsights = false

  private var isEditing: Bool {
    profile != nil
  }

  private var isBlocking: Bool {
    strategyManager.activeSession?.isActive ?? false
  }

  init(profile: BlockedProfiles? = nil) {
    self.profile = profile
    _draft = StateObject(wrappedValue: BlockedProfileDraft(profile: profile))
  }

  var body: some View {
    NavigationStack {
      Form {
        // Show lock status when profile is active
        if isBlocking {
          Section {
            HStack {
              Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundColor(.orange)
              Text("A session is active. Stop it before editing this profile.")
                .font(.subheadline)
                .foregroundColor(.red)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 4)
          }
        }

        BlockedProfileNameSection(draft: draft, disabled: false)

        BlockedProfileStrategySection(
          draft: draft,
          disabled: isBlocking
        )

        BlockedProfileAppsSection(
          draft: draft,
          showingActivityPicker: $showingActivityPicker,
          disabled: isBlocking
        )

        BlockedProfileDomainsSection(
          draft: draft,
          showingDomainPicker: $showingDomainPicker,
          disabled: isBlocking
        )

        BlockedProfileStrictUnlocksSection(draft: draft, disabled: isBlocking)

        BlockedProfileBreaksSection(draft: draft, disabled: isBlocking)

        BlockedProfileStrictSafeguardsSection(draft: draft, disabled: isBlocking)

      }
      .navigationTitle(isEditing ? "Edit Profile" : "New Profile")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: { attemptDismiss() }) {
            Image(systemName: "xmark")
          }
          .accessibilityLabel("Cancel")
        }

        if isEditing, let validProfile = profile {
          ToolbarItemGroup(placement: .topBarTrailing) {
            if !isBlocking {
              Menu {
                Button {
                  cloneName = String(localized: "\(validProfile.name) Copy")
                  showingClonePrompt = true
                } label: {
                  Label("Duplicate Profile", systemImage: "square.on.square")
                }

                Divider()

                Button(role: .destructive) {
                  alertIdentifier = AlertIdentifier(id: .deleteProfile)
                } label: {
                  Label("Delete Profile", systemImage: "trash")
                }
              } label: {
                Image(systemName: "ellipsis.circle")
              }
              .accessibilityLabel("Profile Actions")
            }

            Button(action: { showingInsights = true }) {
              Image(systemName: "chart.line.uptrend.xyaxis")
            }
            .accessibilityLabel("View Insights")
          }
        }

        if #available(iOS 26.0, *) {
          ToolbarSpacer(.flexible, placement: .topBarTrailing)
        }

        if !isBlocking {
          ToolbarItem(placement: .topBarTrailing) {
            Button(action: { saveProfile() }) {
              Image(systemName: "checkmark")
            }
            .disabled(!draft.isValid)
            .accessibilityLabel(isEditing ? "Update" : "Create")
          }
        }
      }
      .sheet(isPresented: $showingActivityPicker) {
        AppPicker(
          selection: $draft.selectedActivity,
          isPresented: $showingActivityPicker,
          allowMode: draft.enableAllowMode
        )
      }
      .sheet(isPresented: $showingDomainPicker) {
        DomainPicker(
          domains: $draft.domains,
          isPresented: $showingDomainPicker,
          allowMode: draft.enableAllowModeDomain
        )
      }
      .sheet(isPresented: $showingInsights) {
        if let validProfile = profile {
          ProfileInsightsView(profile: validProfile)
        }
      }
      .background(
        TextFieldAlert(
          isPresented: $showingClonePrompt,
          title: String(localized: "Duplicate Profile"),
          message: nil,
          text: $cloneName,
          placeholder: String(localized: "Profile Name"),
          confirmTitle: String(localized: "Create"),
          cancelTitle: String(localized: "Cancel"),
          onConfirm: { enteredName in
            let trimmed = enteredName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            do {
              if let source = profile {
                let clonedProfile = try BlockedProfiles.cloneProfile(
                  source, in: modelContext, newName: trimmed)
                DeviceActivityCenterUtil.scheduleTimerActivity(for: clonedProfile)
              }
            } catch {
              showError(message: error.localizedDescription)
            }
          }
        )
      )
      .alert(item: $alertIdentifier) { alert in
        switch alert.id {
        case .error:
          return Alert(
            title: Text("Error"),
            message: Text(alert.errorMessage ?? "An unknown error occurred"),
            dismissButton: .default(Text("OK"))
          )
        case .deleteProfile:
          return Alert(
            title: Text("Delete Profile"),
            message: Text(
              "Are you sure you want to delete this profile? This action cannot be undone."),
            primaryButton: .cancel(),
            secondaryButton: .destructive(Text("Delete")) {
              dismiss()
              if let profileToDelete = profile {
                do {
                  try BlockedProfiles.deleteProfile(profileToDelete, in: modelContext)
                } catch {
                  showError(message: error.localizedDescription)
                }
              }
            }
          )
        case .missingPhysicalUnlock:
          return Alert(
            title: Text("Warning!"),
            message: Text("Set a Physical Unlock to continue."),
            dismissButton: .default(Text("OK"))
          )
        case .discardChanges:
          return Alert(
            title: Text("Discard Changes?"),
            message: Text("You have unsaved changes. Are you sure you want to discard them?"),
            primaryButton: .destructive(Text("Discard")) { dismiss() },
            secondaryButton: .cancel()
          )
        }
      }
      .interactiveDismissDisabled(draft.isDirty)
    }
  }

  private func showError(message: String) {
    alertIdentifier = AlertIdentifier(id: .error, errorMessage: message)
  }

  private func attemptDismiss() {
    if draft.isDirty {
      alertIdentifier = AlertIdentifier(id: .discardChanges)
    } else {
      dismiss()
    }
  }

  private func saveProfile() {
    guard !draft.physicalUnblockItems.isEmpty else {
      alertIdentifier = AlertIdentifier(id: .missingPhysicalUnlock)
      return
    }

    do {
      _ = try draft.save(existingProfile: profile, in: modelContext)
      dismiss()
    } catch {
      alertIdentifier = AlertIdentifier(id: .error, errorMessage: error.localizedDescription)
    }
  }
}

// Preview provider for SwiftUI previews
#Preview {
  BlockedProfileView()
    .environmentObject(StrategyManager())
    .modelContainer(for: BlockedProfiles.self, inMemory: true)
}

#Preview {
  let previewProfile = BlockedProfiles(
    name: "test",
    selectedActivity: FamilyActivitySelection(),
    reminderTimeInSeconds: 60
  )

  BlockedProfileView(profile: previewProfile)
    .environmentObject(StrategyManager())
    .modelContainer(for: BlockedProfiles.self, inMemory: true)
}
