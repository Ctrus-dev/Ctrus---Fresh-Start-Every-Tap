import FamilyControls
import SwiftUI

private struct ProfileFieldDivider: View {
  var isVisible: Bool

  var body: some View {
    if isVisible {
      Divider()
    }
  }
}

struct BlockedProfileNameFields: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool
  var showsFieldLabels: Bool = true

  var body: some View {
    TextField(
      showsFieldLabels ? "Profile Name" : "",
      text: $draft.name,
      prompt: Text("Profile Name")
    )
    .textContentType(.none)
    .disabled(disabled)
  }
}

struct BlockedProfileNameSection: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool

  var body: some View {
    Section("Name") {
      BlockedProfileNameFields(draft: draft, disabled: disabled)
    }
  }
}

struct BlockedProfileStrategyFields: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool
  var showsSeparators: Bool = false

  var body: some View {
    ForEach(Array(StrategyManager.pickerStrategies.enumerated()), id: \.element.name) {
      index, strategy in
      if index > 0 {
        ProfileFieldDivider(isVisible: showsSeparators)
      }

      StrategyRow(
        strategy: strategy,
        isSelected: draft.selectedStrategy?.getIdentifier() == strategy.getIdentifier(),
        onTap: {
          draft.selectedStrategy = strategy
        }
      )
      .disabled(disabled)
    }
  }
}

struct BlockedProfileStrategySection: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool

  var body: some View {
    Section {
      BlockedProfileStrategyFields(
        draft: draft,
        disabled: disabled
      )
    } header: {
      Text("Blocking Strategy")
    }
  }
}

struct BlockedProfileAppsFields: View {
  @ObservedObject var draft: BlockedProfileDraft
  @Binding var showingActivityPicker: Bool
  var disabled: Bool
  var showsSeparators: Bool = false

  var body: some View {
    BlockedProfileAppSelector(
      selection: draft.selectedActivity,
      buttonAction: { showingActivityPicker = true },
      allowMode: draft.enableAllowMode,
      disabled: disabled
    )

    ProfileFieldDivider(isVisible: showsSeparators)

    CustomToggle(
      title: "Allow Only Selected Apps",
      description:
        "Only selected apps stay available during sessions. Turning this on clears your blocked-app selection.",
      isOn: $draft.enableAllowMode,
      isDisabled: disabled
    )

    ProfileFieldDivider(isVisible: showsSeparators)

    CustomToggle(
      title: "Block Websites in Safari",
      description:
        "Also block selected websites in Safari. When off, Safari stays unrestricted.",
      isOn: $draft.enableSafariBlocking,
      isDisabled: disabled
    )
    .onChange(of: draft.enableAllowMode) { _, newValue in
      draft.selectedActivity = FamilyActivitySelection(includeEntireCategory: newValue)
    }
  }
}

struct BlockedProfileAppsSection: View {
  @ObservedObject var draft: BlockedProfileDraft
  @Binding var showingActivityPicker: Bool
  var disabled: Bool

  var body: some View {
    Section((draft.enableAllowMode ? "Allowed" : "Blocked") + " Apps") {
      BlockedProfileAppsFields(
        draft: draft,
        showingActivityPicker: $showingActivityPicker,
        disabled: disabled
      )
    }
  }
}

struct BlockedProfileDomainsFields: View {
  @ObservedObject var draft: BlockedProfileDraft
  @Binding var showingDomainPicker: Bool
  var disabled: Bool
  var showsSeparators: Bool = false

  var body: some View {
    BlockedProfileDomainSelector(
      domains: draft.domains,
      buttonAction: { showingDomainPicker = true },
      allowMode: draft.enableAllowModeDomain,
      disabled: disabled
    )

    ProfileFieldDivider(isVisible: showsSeparators)

    CustomToggle(
      title: "Allow Only Selected Domains",
      description:
        "Only selected domains stay available during sessions. Turning this on clears your blocked-domain selection.",
      isOn: $draft.enableAllowModeDomain,
      isDisabled: disabled
    )

    ProfileFieldDivider(isVisible: showsSeparators)

    CustomToggle(
      title: "Block Adult Websites",
      description:
        "Use Apple's adult-content filter during sessions. You can still add extra domains to block.",
      isOn: $draft.enableAdultContentBlocking,
      isDisabled: disabled
    )
    .onChange(of: draft.enableAllowModeDomain) { _, newValue in
      if newValue {
        draft.enableAdultContentBlocking = false
      }
    }
    .onChange(of: draft.enableAdultContentBlocking) { _, newValue in
      if newValue {
        draft.enableAllowModeDomain = false
      }
    }
  }
}

struct BlockedProfileDomainsSection: View {
  @ObservedObject var draft: BlockedProfileDraft
  @Binding var showingDomainPicker: Bool
  var disabled: Bool

  var body: some View {
    Section((draft.enableAllowModeDomain ? "Allowed" : "Blocked") + " Domains") {
      BlockedProfileDomainsFields(
        draft: draft,
        showingDomainPicker: $showingDomainPicker,
        disabled: disabled
      )
    }
  }
}

struct BlockedProfileStrictUnlocksFields: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool

  var body: some View {
    BlockedProfilePhysicalUnblockSelector(
      physicalUnblockItems: $draft.physicalUnblockItems,
      disabled: disabled
    )
  }
}

struct BlockedProfileStrictUnlocksSection: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool

  var body: some View {
    Section("Physical Unlocks") {
      BlockedProfileStrictUnlocksFields(draft: draft, disabled: disabled)
    }
  }
}

struct BlockedProfileBreaksFields: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool
  var showsSeparators: Bool = false

  @ViewBuilder
  var body: some View {
    if draft.selectedStrategyAllowsTimedBreaks {
      CustomToggle(
        title: "Allow Timed Breaks",
        description:
          "Take a break during your session. The break will automatically end after the selected duration.",
        isOn: $draft.enableBreaks,
        isDisabled: disabled
      )

      if draft.enableBreaks {
        ProfileFieldDivider(isVisible: showsSeparators)

        breakDurationPicker

        ProfileFieldDivider(isVisible: showsSeparators)

        CustomToggle(
          title: "Allow Multiple Breaks",
          description: "Take multiple breaks until your total break duration is used.",
          isOn: $draft.allowMultipleBreaks,
          isDisabled: disabled
        )
      }
    } else {
      ProfileFieldNotice(
        title: "Breaks are off for Temporary Access",
        message:
          "This strategy already gives short opens for blocked apps and categories, so timed breaks are not needed for this profile."
      )
    }
  }

  private var breakDurationPicker: some View {
    Picker("Break Duration", selection: $draft.breakTimeInMinutes) {
      Text("5 minutes").tag(5)
      Text("10 minutes").tag(10)
      Text("15 minutes").tag(15)
    }
    .disabled(disabled)
  }
}

struct BlockedProfileBreaksSection: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool

  var body: some View {
    Section("Breaks") {
      BlockedProfileBreaksFields(draft: draft, disabled: disabled)
    }
  }
}

private struct ProfileFieldNotice: View {
  let title: String
  let message: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundStyle(.primary)

      Text(message)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }
}

struct BlockedProfileStrictSafeguardsFields: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool
  var showsSeparators: Bool = false

  var body: some View {
    CustomToggle(
      title: "Prevent App Deletion",
      description:
        "Stop apps from being deleted during sessions, including Ctrus.",
      isOn: $draft.enableStrictMode,
      isDisabled: disabled
    )

    ProfileFieldDivider(isVisible: showsSeparators)

    CustomToggle(
      title: "Prevent New App Installs",
      description:
        "Stop new apps from being installed during sessions.",
      isOn: $draft.enableBlockAppInstallation,
      isDisabled: disabled
    )
  }
}

struct BlockedProfileStrictSafeguardsSection: View {
  @ObservedObject var draft: BlockedProfileDraft
  var disabled: Bool

  var body: some View {
    Section("Session Protection") {
      BlockedProfileStrictSafeguardsFields(draft: draft, disabled: disabled)
    }
  }
}

