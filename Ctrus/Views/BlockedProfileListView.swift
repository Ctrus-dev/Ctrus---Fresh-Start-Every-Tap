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
        if profiles.isEmpty {
          ScrollView {
            VStack {
              Spacer(minLength: 70)

              Welcome(
                onGuidedTap: {
                  if canCreateProfiles {
                    showingGuidedCreation = true
                  }
                }
              )

              Spacer(minLength: 70)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
          }
        } else {
          List {
            ForEach(profiles) { profile in
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
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
            .onDelete(perform: editMode == .active ? deleteProfiles : nil)
            .onMove(perform: editMode == .active ? moveProfiles : nil)
          }
          .listStyle(.plain)
          .environment(\.editMode, $editMode)
        }
      }
      .navigationTitle("Profiles")
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
          if !profiles.isEmpty {
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

  private func deleteProfiles(at offsets: IndexSet) {
    let activeSession = BlockedProfileSession.mostRecentActiveSession(
      in: context)

    // Check if any of the profiles to delete are active
    for index in offsets {
      let profile = profiles[index]
      if profile.id == activeSession?.blockedProfile.id {
        showErrorAlert = true
        return
      }
    }

    // Delete the profiles and reorder
    do {
      for index in offsets {
        let profile = profiles[index]
        try BlockedProfiles.deleteProfile(profile, in: context)
      }

      // Reorder remaining profiles to fix gaps in ordering
      let remainingProfiles = try BlockedProfiles.fetchProfiles(in: context)
      try BlockedProfiles.reorderProfiles(remainingProfiles, in: context)
    } catch {
      print("Failed to delete or reorder profiles: \(error)")
    }
  }

  private func moveProfiles(from source: IndexSet, to destination: Int) {
    var reorderedProfiles = Array(profiles)
    reorderedProfiles.move(fromOffsets: source, toOffset: destination)

    do {
      try BlockedProfiles.reorderProfiles(reorderedProfiles, in: context)
    } catch {
      print("Failed to reorder profiles: \(error)")
    }
  }
}

#Preview {
  BlockedProfileListView()
    .environmentObject(ThemeManager.shared)
    .modelContainer(for: BlockedProfiles.self, inMemory: true)
}
