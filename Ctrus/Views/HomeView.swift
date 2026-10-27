import SwiftData
import SwiftUI

struct HomeView: View {
  @Environment(\.modelContext) private var context
  @Environment(\.openURL) var openURL

  @Environment(\.scenePhase) private var scenePhase

  @EnvironmentObject var requestAuthorizer: RequestAuthorizer
  @EnvironmentObject var strategyManager: StrategyManager
  @EnvironmentObject var alertsManager: AlertsManager
  @EnvironmentObject var navigationManager: NavigationManager
  @EnvironmentObject var ratingManager: RatingManager
  @EnvironmentObject var themeManager: ThemeManager

  // Profile management
  @Query(sort: [
    SortDescriptor(\BlockedProfiles.order, order: .forward),
    SortDescriptor(\BlockedProfiles.createdAt, order: .reverse),
  ]) private
    var profiles: [BlockedProfiles]

  // Schedule-mode profiles only ever start on their own, so they're left out
  // of the manual start picker rather than offered and then refused.
  private var manuallyStartableProfiles: [BlockedProfiles] {
    profiles.filter { $0.blockingStrategyId != ScheduleBlockingStrategy.id }
  }
  @State private var isProfileListPresent = false

  // New profile view
  @State private var showGuidedProfileCreationView = false
  @State private var showStartProfilePicker = false

  // Edit profile
  @State private var profileToEdit: BlockedProfiles? = nil

  // Stats sheet
  @State private var profileToShowStats: BlockedProfiles? = nil

  // Dashboard insights sheet
  @State private var dashboardInsightsContext: DashboardInsightsContext? = nil

  // Settings View
  @State private var showSettingsView = false

  // Skipping schedule sessions
  @State private var scheduleSkipUtil = ScheduleSkipUtil()
  @State private var profileToSkipUntil: BlockedProfiles? = nil
  @State private var skipUntilErrorMessage: String? = nil
  @State private var toastMessage: String? = nil
  @State private var parentConfirmationRequest: ParentConfirmationRequest? = nil
  @State private var lastUnseenTamperDate: Date? = nil
  @State private var showTamperLog = false

  // Navigate to profile
  @State private var navigateToProfileId: UUID? = nil

  // Activity sessions
  @Query(
    filter: #Predicate<BlockedProfileSession> { $0.endTime != nil },
    sort: \BlockedProfileSession.endTime,
    order: .reverse
  ) private var recentCompletedSessions: [BlockedProfileSession]

  // Alerts
  @State private var showingAlert = false
  @State private var alertTitle = ""
  @State private var alertMessage = ""

  // A deep link (e.g. a universal link tapped outside the app) that would
  // stop the active session needs confirmation before it's carried out —
  // see `pendingDeepLinkStopAction`.
  @State private var pendingDeepLinkStopAction: StrategyManager.DeepLinkSessionAction? = nil

  // Intro sheet
  @AppStorage("showIntroScreen") private var showIntroScreen = true
  @AppStorage("pendingChildModeSetup") private var pendingChildModeSetup = false
  @AppStorage("hasChosenAppMode") private var hasChosenAppMode = false

  // Small how-to caption under the profile list, shown until the person
  // completes their very first session.
  @AppStorage("hasCompletedFirstSession") private var hasCompletedFirstSession = false

  // UI States
  @State private var opacityValue = 1.0

  // Hides the Activity habit tracker on the home page without removing it from the codebase.
  private let showActivityTracker = false

  var isBlocking: Bool {
    return strategyManager.isBlocking
  }

  var activeSessionProfileId: UUID? {
    return strategyManager.activeSession?.blockedProfile.id
  }

  var isBreakAvailable: Bool {
    return strategyManager.isBreakAvailable
  }

  var isBreakActive: Bool {
    return strategyManager.isBreakActive
  }

  var isPauseActive: Bool {
    return strategyManager.isPauseActive
  }

  private var canCreateProfiles: Bool {
    return !isBlocking
  }

  var body: some View {
    ZStack {
      themeManager.pastelBackground
        .ignoresSafeArea()

      pageBody
    }
    .frame(
      minWidth: 0,
      maxWidth: .infinity,
      minHeight: 0,
      maxHeight: .infinity,
      alignment: .topLeading
    )
    .onChange(of: navigationManager.profileId) { _, newValue in
      if let profileId = newValue, navigationManager.link != nil {
        toggleSessionFromDeeplink(profileId)
        navigationManager.clearNavigation()
      }
    }
    .onChange(of: navigationManager.navigateToProfileId) { _, newValue in
      if let profileId = newValue {
        // With more than one profile, the picker sheet is more friction than
        // help from a widget tap — just land on the main screen instead.
        if profiles.count <= 1 {
          navigateToProfileId = UUID(uuidString: profileId)
          showStartProfilePicker = true
        }
        navigationManager.clearNavigation()
      }
    }
    .onChange(of: requestAuthorizer.isAuthorized) { _, newValue in
      // Granting access only gets a new install to the mode choice; the
      // intro closes itself once a mode has been picked (and, for child
      // mode, set up).
      if newValue && hasChosenAppMode && !pendingChildModeSetup {
        showIntroScreen = false
      }
      refreshAlerts()
    }
    .onChange(of: profiles) { oldValue, newValue in
      if !newValue.isEmpty {
        loadApp()
      }
      refreshAlerts()
    }
    .onChange(of: scenePhase) { oldPhase, newPhase in
      if newPhase == .active {
        requestAuthorizer.refreshAuthorizationStatus()
        loadApp()
        refreshAlerts()
      } else if newPhase == .background {
        unloadApp()
      }
    }
    .onReceive(strategyManager.$errorMessage) { errorMessage in
      guard let message = errorMessage else { return }
      showErrorAlert(message: message)
    }
    .onAppear {
      onAppearApp()
    }
    .sheet(isPresented: $isProfileListPresent) {
      BlockedProfileListView()
    }
    .sheet(item: $alertsManager.selectedAlert) { alert in
      HomeAlertDetailView(
        alert: alert,
        disabledReason: disabledReason(for: alert),
        onPrimaryAction: {
          runAlertPrimaryAction(for: alert)
        }
      )
      // .medium clipped the primary button on short screens (e.g. iPhone SE),
      // so those fall back to .large; taller screens keep the partial sheet.
      .presentationDetents(
        RotatingModel3DView.isCompactScreen ? [.large] : [.medium, .large]
      )
    }
    .fullScreenCover(isPresented: $showIntroScreen) {
      IntroView(
        onRequestAuthorization: {
          requestAuthorizer.requestAuthorization()
        },
        onFinished: {
          showIntroScreen = false
        }
      )
      .interactiveDismissDisabled()
    }
    .sheet(item: $profileToShowStats) { profile in
      ProfileInsightsView(profile: profile)
    }
    .sheet(item: $profileToEdit) { profile in
      BlockedProfileView(profile: profile)
    }
    .sheet(item: $dashboardInsightsContext) { context in
      ProfileInsightsView(
        profile: context.profile,
        initialViewMode: context.viewMode,
        initialSelectedDate: context.selectedDate
      )
    }
    .sheet(isPresented: $showGuidedProfileCreationView) {
      GuidedBlockedProfileCreationView()
    }
    .sheet(isPresented: $showStartProfilePicker) {
      StartProfilePickerView(
        profiles: manuallyStartableProfiles,
        isBlocking: isBlocking,
        activeSessionProfileId: activeSessionProfileId,
        startingProfileId: navigateToProfileId,
        onGoTapped: { profile in
          startProfile(profile)
        }
      )
      .presentationDetents([.medium, .large])
    }
    .sheet(isPresented: strategyActionSheetBinding) {
      BlockingStrategyActionView(
        customView: strategyManager.customStrategyView,
        presentationDetents: strategyManager.customStrategyViewPresentationDetents
      )
    }
    .sheet(isPresented: $showSettingsView) {
      SettingsView()
    }
    .sheet(item: $profileToSkipUntil) { profile in
      if let schedule = profile.schedule {
        SkipUntilView(schedule: schedule, errorMessage: $skipUntilErrorMessage) { day in
          skipUntil(day, for: profile)
        }
        .presentationDetents([.large])
      }
    }
    .toastBanner(message: $toastMessage)
    .parentConfirmation($parentConfirmationRequest)
    .sheet(isPresented: $showTamperLog, onDismiss: refreshTamperBanner) {
      NavigationStack {
        TamperLogView()
          .toolbar {
            ToolbarItem(placement: .topBarLeading) {
              Button(action: { showTamperLog = false }) {
                Image(systemName: "xmark")
              }
              .accessibilityLabel("Close")
            }
          }
      }
    }
    .alert(alertTitle, isPresented: $showingAlert) {
      Button("OK", role: .cancel) { dismissAlert() }
    } message: {
      Text(alertMessage)
    }
    .alert(
      "Stop your session?",
      isPresented: Binding(
        get: { pendingDeepLinkStopAction != nil },
        set: { isPresented in
          if !isPresented { pendingDeepLinkStopAction = nil }
        }
      )
    ) {
      Button("Stop", role: .destructive) {
        if let action = pendingDeepLinkStopAction {
          strategyManager.performDeepLinkAction(action, context: context)
        }
        pendingDeepLinkStopAction = nil
      }
      Button("Cancel", role: .cancel) {
        pendingDeepLinkStopAction = nil
      }
    } message: {
      Text("A link is trying to stop your active session. Only continue if you opened this yourself.")
    }
  }

  private var pageBody: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: 30) {
        HStack(alignment: .center) {
          HomeAlertsView(
            alerts: alertsManager.alerts,
            onAlertTapped: { alert in
              presentAlert(alert)
            }
          )

          Spacer()
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.top, 16)

        if let lastUnseenTamperDate {
          tamperBanner(since: lastUnseenTamperDate)
            .padding(.horizontal, 16)
        }

        RotatingModel3DView(themeColor: themeManager.themeColor)
          .frame(maxWidth: .infinity, alignment: .center)

        if profiles.isEmpty {
          Welcome(
            onGuidedTap: {
              if canCreateProfiles {
                showGuidedProfileCreationView = true
              }
            }
          )
          .padding(.horizontal, 16)
        }

        if !profiles.isEmpty {
          if showActivityTracker {
            BlockedSessionsHabitTracker(
              sessions: recentCompletedSessions,
              profiles: profiles,
              onInsightsTapped: { context in
                dashboardInsightsContext = context
              }
            )
            .padding(.horizontal, 16)
          }

          VStack(alignment: .leading, spacing: 10) {
            HomeProfilesListView(
              profiles: profiles,
              isBlocking: isBlocking,
              isAuthorized: requestAuthorizer.isAuthorized,
              activeSessionProfileId: activeSessionProfileId,
              elapsedTime: strategyManager.elapsedTime,
              displayTime: strategyManager.sessionDisplayTime,
              isBreakActive: isBreakActive,
              isBreakAvailable: isBreakAvailable,
              isPauseActive: isPauseActive,
              onManageTapped: {
                isProfileListPresent = true
              },
              onSettingsTapped: {
                showSettingsView = true
              },
              onStartTapped: { profile in
                startProfile(profile)
              },
              onStopTapped: { profile in
                strategyButtonPress(profile)
              },
              onEditTapped: { profile in
                profileToEdit = profile
              },
              onStatsTapped: { profile in
                profileToShowStats = profile
              },
              onBreakTapped: {
                strategyManager.toggleBreak(context: context)
              },
              onSkipNextTapped: { profile in
                skipNextOccurrence(for: profile)
              },
              onSkipUntilTapped: { profile in
                profileToSkipUntil = profile
              },
              onResumeScheduleTapped: { profile in
                scheduleSkipUtil.resume(profile, in: context)
              }
            )

            if !hasCompletedFirstSession {
              sessionHintText
            }
          }
          .padding(.horizontal, 16)
        }
      }
    }
    .scrollContentBackground(.hidden)
    .refreshable {
      loadApp()
    }
    .padding(.top, 1)
  }

  private var sessionHintText: some View {
    Text(
      "Press and hold your profile to start the session. Tap it while it's active to access the stop, emergency and break options."
    )
      .font(.subheadline)
      // This screen's background stays a fixed light pastel regardless of
      // the system's Light/Dark setting, so `.secondary` (which adapts to
      // it) went near-white-on-light-cream and was unreadable in Dark Mode.
      // Matches the "First Steps" subtitle in Welcome.swift.
      .foregroundStyle(Color.fixedLightSecondaryText)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity, alignment: .center)
  }

  private func toggleSessionFromDeeplink(_ profileId: String) {
    let action = strategyManager.resolveDeepLinkAction(profileId, context: context)

    switch action {
    case .stop:
      // Opening a link should never silently end a session — confirm first.
      pendingDeepLinkStopAction = action
    default:
      strategyManager.performDeepLinkAction(action, context: context)
    }
  }

  private func strategyButtonPress(_ profile: BlockedProfiles) {
    strategyManager
      .toggleBlocking(context: context, activeProfile: profile)

    ratingManager.incrementLaunchCount()
  }

  private var strategyActionSheetBinding: Binding<Bool> {
    Binding(
      get: {
        strategyManager.showCustomStrategyView
      },
      set: { isPresented in
        if !isPresented {
          strategyManager.showCustomStrategyView = false
        }
      }
    )
  }

  private func startProfile(_ profile: BlockedProfiles) {
    guard !alertsManager.presentScreenTimeAccessAlertIfNeeded() else { return }

    guard !isBlocking else {
      showErrorAlert(
        message: String(localized: "Stop the active profile before starting another one."))
      return
    }

    strategyButtonPress(profile)
  }

  private func loadApp() {
    checkChildMode()
    strategyManager.loadActiveSession(context: context)
    strategyManager.checkAndResetEmergencyUnblocks()
    strategyManager.checkAndResetRecoveryUnlocks()
    BlockedProfiles.clearExpiredScheduleSkips(in: context)
  }

  private func skipNextOccurrence(for profile: BlockedProfiles) {
    guard ChildModeStore.isChildMode else {
      skipNextOccurrence(for: profile, alreadyConfirmed: false)
      return
    }

    parentConfirmationRequest = ParentConfirmationRequest(
      reason: String(localized: "To skip sessions")
    ) {
      skipNextOccurrence(for: profile, alreadyConfirmed: true)
    }
  }

  private func skipNextOccurrence(for profile: BlockedProfiles, alreadyConfirmed: Bool) {
    scheduleSkipUtil.skipNextOccurrence(
      of: profile,
      in: context,
      alreadyConfirmed: alreadyConfirmed,
      onSuccess: { message in
        toastMessage = message
      },
      onError: { message in
        showErrorAlert(message: message)
      }
    )
  }

  private func skipUntil(_ day: Date, for profile: BlockedProfiles) {
    scheduleSkipUtil.skipUntil(
      day,
      of: profile,
      in: context,
      alreadyConfirmed: ChildModeStore.isChildMode,
      onSuccess: { message in
        profileToSkipUntil = nil
        toastMessage = message
      },
      onError: { message in
        skipUntilErrorMessage = message
      }
    )
  }

  // Catches up on anything the device monitor may have missed while the app
  // was closed: an automatic end that's already due, or a moved date.
  private func checkChildMode() {
    guard ChildModeStore.isChildMode else {
      lastUnseenTamperDate = nil
      return
    }
    ChildModeStore.checkForClockChange()
    ChildSessionLimit.check()
    refreshTamperBanner()
  }

  private func refreshTamperBanner() {
    lastUnseenTamperDate =
      ChildModeStore.isChildMode && ChildModeStore.tamperLogUnseen
      ? ChildModeStore.tamperLog.last?.at : nil
  }

  private func tamperBanner(since date: Date) -> some View {
    let when = RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())

    return Button {
      parentConfirmationRequest = ParentConfirmationRequest(
        reason: String(localized: "To see the attempt log")
      ) {
        showTamperLog = true
      }
    } label: {
      HStack(spacing: 10) {
        Image(systemName: "exclamationmark.shield.fill")
          .foregroundStyle(.red)
        Text("Protection was turned off \(when). See log.")
          .font(.subheadline)
          .foregroundStyle(Color.fixedLightPrimaryText)
          .multilineTextAlignment(.leading)
        Spacer(minLength: 0)
      }
      .padding(14)
      .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(Color.red.opacity(0.6), lineWidth: 1.5)
      )
    }
    .buttonStyle(.plain)
  }

  private func onAppearApp() {
    requestAuthorizer.refreshAuthorizationStatus()
    checkChildMode()
    strategyManager.loadActiveSession(context: context)
    strategyManager.checkAndResetEmergencyUnblocks()
    strategyManager.checkAndResetRecoveryUnlocks()
    BlockedProfiles.clearExpiredScheduleSkips(in: context)
    strategyManager.cleanUpGhostSchedules(context: context)
    refreshAlerts()
  }

  private func refreshAlerts() {
    alertsManager.refreshAlerts(
      profiles: profiles,
      authorizationStatus: requestAuthorizer.getAuthorizationStatus()
    )
  }

  private func presentAlert(_ alert: HomeAlert) {
    alertsManager.present(alert)
  }

  private func disabledReason(for alert: HomeAlert) -> String? {
    return alertsManager.disabledReason(
      for: alert,
      profiles: profiles,
      isBlocking: isBlocking
    )
  }

  private func runAlertPrimaryAction(for alert: HomeAlert) {
    alertsManager.runPrimaryAction(
      for: alert,
      profiles: profiles,
      isBlocking: isBlocking,
      requestAuthorizer: requestAuthorizer,
      onScheduleRepaired: {
        loadApp()
        refreshAlerts()
      }
    )
  }

  private func unloadApp() {
    strategyManager.stopTimer()
  }

  private func showErrorAlert(message: String) {
    alertTitle = String(localized: "Whoops")
    alertMessage = message
    showingAlert = true
  }

  private func dismissAlert() {
    showingAlert = false
    strategyManager.errorMessage = nil
  }
}

#Preview {
  HomeView()
    .environmentObject(RequestAuthorizer())
    .environmentObject(AlertsManager())
    .environmentObject(NavigationManager())
    .environmentObject(StrategyManager())
    .environmentObject(ThemeManager.shared)
    .defaultAppStorage(UserDefaults(suiteName: "preview")!)
    .onAppear {
      UserDefaults(suiteName: "preview")!.set(
        false,
        forKey: "showIntroScreen"
      )
    }
}
