import FamilyControls
import SwiftData
import SwiftUI

struct BlockedProfileListView: View {
  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var themeManager: ThemeManager

  @Query(sort: [
    SortDescriptor(\BlockedProfiles.order, order: .forward),
    SortDescriptor(\BlockedProfiles.createdAt, order: .reverse),
  ]) private var profiles: [BlockedProfiles]

  @Query(
    filter: #Predicate<BlockedProfileSession> { $0.endTime == nil },
    sort: \BlockedProfileSession.startTime,
    order: .reverse
  ) private var activeSessions: [BlockedProfileSession]

  @State private var showingGuidedCreation = false

  @State private var profileToEdit: BlockedProfiles?
  @State private var showErrorAlert = false
  @State private var editMode: EditMode = .inactive

  var body: some View {
    NavigationStack {
      Group {
        if !profiles.isEmpty {
          List {
            ForEach(profiles) { profile in
              HStack(spacing: 12) {
                // Edit stays on the leading side; delete moves to the
                // trailing side (replacing the system's reorder handle)
                // so the two aren't next to each other and easy to mix up.
                if editMode == .active {
                  Button(action: { profileToEdit = profile }) {
                    Image(systemName: "pencil.circle.fill")
                      .font(.title2)
                      .foregroundStyle(.gray)
                  }
                  .buttonStyle(.plain)
                }

                ProfileRow(profile: profile, isActive: profile.id == activeSessionProfileId)
                  .padding(14)
                  .background(
                    Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                  )
                  .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                      .strokeBorder(themeManager.themeColor, lineWidth: 3.5)
                  )
                  .contentShape(Rectangle())
                  .onTapGesture {
                    if editMode == .inactive {
                      profileToEdit = profile
                    }
                  }

                if editMode == .active {
                  Button(action: { deleteProfile(profile) }) {
                    Image(systemName: "minus.circle.fill")
                      .font(.title2)
                      .foregroundStyle(.red)
                  }
                  .buttonStyle(.plain)
                }
              }
              .listRowSeparator(.hidden)
              .listRowBackground(Color.clear)
              .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
          }
          .listStyle(.plain)
        }
      }
      .navigationTitle("Profiles")
      .onChange(of: profiles) { _, newValue in
        if newValue.isEmpty {
          dismiss()
        }
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: { dismiss() }) {
            Image(systemName: "xmark")
          }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
          if editMode == .active {
            Button(action: { editMode = .inactive }) {
              Image(systemName: "checkmark.circle")
            }
          }
          if editMode == .inactive && !profiles.isEmpty {
            Button(action: { editMode = .active }) {
              Image(systemName: "pencil")
            }
            .accessibilityLabel("Edit/Move")
          }
          if canCreateProfiles {
            Button {
              showingGuidedCreation = true
            } label: {
              Image(systemName: "plus")
            }
          }
        }
      }
      .sheet(isPresented: $showingGuidedCreation) {
        GuidedBlockedProfileCreationView()
      }
      .sheet(item: $profileToEdit) { profile in
        BlockedProfileView(profile: profile)
      }
      .alert(
        "Cannot Delete Active Profile",
        isPresented: $showErrorAlert
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(
          "You cannot delete a profile that is currently active. Please switch to a different profile first."
        )
      }
    }
  }

  private var activeSessionProfileId: UUID? {
    activeSessions.first?.blockedProfile.id
  }

  private var canCreateProfiles: Bool {
    return activeSessionProfileId == nil
  }

  private func deleteProfile(_ profile: BlockedProfiles) {
    let activeSession = BlockedProfileSession.mostRecentActiveSession(in: context)
    if profile.id == activeSession?.blockedProfile.id {
      showErrorAlert = true
      return
    }

    do {
      try BlockedProfiles.deleteProfile(profile, in: context)

      // Reorder remaining profiles to fix gaps in ordering
      let remainingProfiles = try BlockedProfiles.fetchProfiles(in: context)
      try BlockedProfiles.reorderProfiles(remainingProfiles, in: context)
    } catch {
      print("Failed to delete or reorder profile: \(error)")
    }
  }

}

#Preview {
  BlockedProfileListView()
    .environmentObject(ThemeManager.shared)
    .modelContainer(for: BlockedProfiles.self, inMemory: true)
}
