import SwiftUI

struct HomeProfilesListView: View {
  @EnvironmentObject private var themeManager: ThemeManager

  @AppStorage("useLeftHandedLayout") private var useLeftHandedLayout = false

  let profiles: [BlockedProfiles]
  let isBlocking: Bool
  let isAuthorized: Bool
  let activeSessionProfileId: UUID?
  let elapsedTime: TimeInterval
  var displayTime: TimeInterval = 0
  var isBreakActive = false
  var isBreakAvailable = false
  let isPauseActive: Bool
  let onManageTapped: () -> Void
  let onSettingsTapped: () -> Void
  let onStartTapped: (BlockedProfiles) -> Void
  let onStopTapped: (BlockedProfiles) -> Void
  let onEditTapped: (BlockedProfiles) -> Void
  let onStatsTapped: (BlockedProfiles) -> Void
  var onBreakTapped: () -> Void = {}

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        if useLeftHandedLayout {
          RoundedButton("", action: onSettingsTapped, iconName: "gear", forcedLight: true)
          RoundedButton(
            "", action: onManageTapped, iconName: "person.crop.circle", forcedLight: true)

          Spacer()
        } else {
          Spacer()

          RoundedButton(
            "", action: onManageTapped, iconName: "person.crop.circle", forcedLight: true)
          RoundedButton("", action: onSettingsTapped, iconName: "gear", forcedLight: true)
        }
      }
      .padding(.bottom, 10)

      VStack(spacing: 12) {
        ForEach(profiles, id: \.id) { profile in
          ProfileBalloonRow(
            profile: profile,
            isBlocking: isBlocking,
            isActive: profile.id == activeSessionProfileId,
            isAuthorized: isAuthorized,
            elapsedTime: elapsedTime,
            displayTime: displayTime,
            isBreakActive: isBreakActive,
            isBreakAvailable: isBreakAvailable,
            isPauseActive: isPauseActive,
            onStartTapped: {
              onStartTapped(profile)
            },
            onStopTapped: {
              onStopTapped(profile)
            },
            onBreakTapped: onBreakTapped,
            onEditTapped: {
              onEditTapped(profile)
            },
            onStatsTapped: {
              onStatsTapped(profile)
            }
          )
        }
      }
    }
  }
}
