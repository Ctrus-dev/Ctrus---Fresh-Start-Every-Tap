import SwiftData
import SwiftUI

private enum InsightsFilter: Equatable {
  case thisWeek
  case lastWeek
  case thisMonth
  case lastMonth
  case specificWeek
  case specificMonth
  case allSessions
}

struct ProfileInsightsView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var themeManager: ThemeManager

  @StateObject private var weeklyViewModel: WeeklyInsightsUtil
  @StateObject private var monthlyViewModel: MonthlyInsightsUtil
  @StateObject private var profileInsightsViewModel: ProfileInsightsUtil
  @State private var selectedWeekDay: WeeklyDayAggregate?
  @State private var selectedMonthDay: MonthlyDayAggregate?
  @State private var showingWeekPicker = false
  @State private var showingMonthPicker = false
  @State private var selectedFilter: InsightsFilter = .thisWeek

  @Query(sort: \BlockedProfileSession.startTime, order: .reverse)
  private var allSessions: [BlockedProfileSession]

  private var viewMode: InsightsViewMode {
    switch selectedFilter {
    case .thisWeek, .lastWeek, .specificWeek:
      return .week
    case .thisMonth, .lastMonth, .specificMonth:
      return .month
    case .allSessions:
      return .allSessions
    }
  }

  private var selectedDay: Any? {
    switch viewMode {
    case .week:
      return selectedWeekDay
    case .month:
      return selectedMonthDay
    case .allSessions:
      return nil
    }
  }

  private var isSpecificFilter: Bool {
    switch selectedFilter {
    case .specificWeek, .specificMonth:
      return true
    default:
      return false
    }
  }

  @State private var initialViewMode: InsightsViewMode?
  @State private var initialSelectedDate: Date?
  @State private var hasAppliedInitialState = false
  private let profileName: String

  init(
    profile: BlockedProfiles,
    initialViewMode: InsightsViewMode? = nil,
    initialSelectedDate: Date? = nil
  ) {
    _weeklyViewModel = StateObject(wrappedValue: WeeklyInsightsUtil(profiles: [profile]))
    _monthlyViewModel = StateObject(wrappedValue: MonthlyInsightsUtil(profiles: [profile]))
    _profileInsightsViewModel = StateObject(wrappedValue: ProfileInsightsUtil(profile: profile))
    _initialViewMode = State(wrappedValue: initialViewMode)
    _initialSelectedDate = State(wrappedValue: initialSelectedDate)
    self.profileName = profile.name
  }

  private var weekSummary: WeeklySummary {
    weeklyViewModel.weeklySummary
  }

  private var monthSummary: MonthlySummary {
    monthlyViewModel.monthlySummary
  }

  // Sessions under a minute round to "0m" wherever duration is displayed —
  // not worth showing as a row.
  private static let minimumDisplayableDuration: TimeInterval = 60

  private var weekSessions: [BlockedProfileSession] {
    allSessions.filter { session in
      guard let profileId = weeklyViewModel.profiles.first?.id,
        session.blockedProfile.id == profileId,
        let endTime = session.endTime,
        session.duration >= Self.minimumDisplayableDuration
      else {
        return false
      }
      return session.startTime < weekEndExclusive && endTime > weekStart
    }
  }

  private var monthSessions: [BlockedProfileSession] {
    allSessions.filter { session in
      guard let profileId = monthlyViewModel.profiles.first?.id,
        session.blockedProfile.id == profileId,
        let endTime = session.endTime,
        session.duration >= Self.minimumDisplayableDuration
      else {
        return false
      }
      return session.startTime < monthEndExclusive && endTime > monthStart
    }
  }

  private var allProfileSessions: [BlockedProfileSession] {
    allSessions.filter { session in
      guard let profileId = weeklyViewModel.profiles.first?.id else { return false }
      return session.blockedProfile.id == profileId && session.endTime != nil
        && session.duration >= Self.minimumDisplayableDuration
    }
  }

  private var filteredSessions: [BlockedProfileSession] {
    switch viewMode {
    case .week:
      return filteredWeekSessions
    case .month:
      return filteredMonthSessions
    case .allSessions:
      return allProfileSessions
    }
  }

  private var filteredWeekSessions: [BlockedProfileSession] {
    guard let selectedWeekDay else {
      return weekSessions
    }

    let dayStart = Calendar.current.startOfDay(for: selectedWeekDay.date)
    let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

    return weekSessions.filter { session in
      guard let endTime = session.endTime else { return false }
      return session.startTime < dayEnd && endTime > dayStart
    }
  }

  private var filteredMonthSessions: [BlockedProfileSession] {
    guard let selectedMonthDay else {
      return monthSessions
    }

    let dayStart = Calendar.current.startOfDay(for: selectedMonthDay.date)
    let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

    return monthSessions.filter { session in
      guard let endTime = session.endTime else { return false }
      return session.startTime < dayEnd && endTime > dayStart
    }
  }

  private var weekStart: Date {
    weekSummary.weekStartDate
  }

  private var weekEndExclusive: Date {
    Calendar.current.date(byAdding: .day, value: 1, to: weekSummary.weekEndDate)
      ?? weekSummary.weekEndDate
  }

  private var monthStart: Date {
    monthSummary.monthStartDate
  }

  private var monthEndExclusive: Date {
    Calendar.current.date(byAdding: .day, value: 1, to: monthSummary.monthEndDate)
      ?? monthSummary.monthEndDate
  }

  private struct SessionDayGroup: Identifiable {
    let day: Date
    let sessions: [BlockedProfileSession]
    var id: Date { day }
  }

  private var groupedSessions: [SessionDayGroup] {
    let calendar = Calendar.current
    var sessionsByDay: [Date: [BlockedProfileSession]] = [:]
    var dayOrder: [Date] = []

    for session in filteredSessions {
      let day = calendar.startOfDay(for: session.startTime)
      if sessionsByDay[day] == nil {
        dayOrder.append(day)
      }
      sessionsByDay[day, default: []].append(session)
    }

    return dayOrder.map { SessionDayGroup(day: $0, sessions: sessionsByDay[$0] ?? []) }
  }

  var body: some View {
    NavigationStack {
      List {
        if viewMode != .allSessions {
          Section {
            if viewMode == .week {
              WeeklySessionChart(
                viewModel: weeklyViewModel, selectedDay: $selectedWeekDay, onDateSelected: nil
              )
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.vertical, 8)
              .listRowInsets(EdgeInsets(top: 12, leading: 4, bottom: 0, trailing: 4))
              .listRowBackground(Color.clear)
            } else {
              MonthlySessionChart(
                viewModel: monthlyViewModel, selectedDay: $selectedMonthDay, onDateSelected: nil
              )
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.vertical, 8)
              .listRowInsets(EdgeInsets(top: 12, leading: 4, bottom: 0, trailing: 4))
              .listRowBackground(Color.clear)
            }
          }
        }

        if selectedDay == nil {
          Section("Summary") {
            InsightsSummaryRow(
              icon: "clock.fill",
              label: String(localized: "Total Focus Time"),
              value: DateFormatters.formatDurationHoursMinutes(
                profileInsightsViewModel.metrics.totalFocusTime)
            )

            InsightsSummaryRow(
              icon: "cup.and.saucer.fill",
              label: String(localized: "Total Break Time"),
              value: DateFormatters.formatDurationHoursMinutes(
                profileInsightsViewModel.metrics.totalBreakTime)
            )
          }
        }

        ForEach(groupedSessions) { group in
          Section(DateFormatters.formatSessionDate(group.day)) {
            ForEach(group.sessions) { session in
              SessionRow(session: session)
            }
          }
        }
      }
      .navigationTitle("\(profileName) Insights")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .accessibilityLabel("Close")
        }

        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            // Week options
            Button {
              selectedFilter = .thisWeek
              clearDaySelection()
              weeklyViewModel.setWeek(for: Date())
            } label: {
              Label(
                "This Week",
                systemImage: selectedFilter == .thisWeek
                  ? "checkmark" : "calendar.day.timeline.left")
            }

            Button {
              selectedFilter = .lastWeek
              clearDaySelection()
              if let lastWeek = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date())
              {
                weeklyViewModel.setWeek(for: lastWeek)
              }
            } label: {
              Label(
                "Last Week",
                systemImage: selectedFilter == .lastWeek
                  ? "checkmark" : "calendar.day.timeline.right")
            }

            Divider()

            // Month options
            Button {
              selectedFilter = .thisMonth
              clearDaySelection()
              monthlyViewModel.setMonth(for: Date())
            } label: {
              Label(
                "This Month", systemImage: selectedFilter == .thisMonth ? "checkmark" : "calendar")
            }

            Button {
              selectedFilter = .lastMonth
              clearDaySelection()
              if let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: Date()) {
                monthlyViewModel.setMonth(for: lastMonth)
              }
            } label: {
              Label(
                "Last Month", systemImage: selectedFilter == .lastMonth ? "checkmark" : "arrow.left"
              )
            }

            Divider()

            // Specific date picker
            Button {
              if viewMode == .week {
                showingWeekPicker = true
              } else if viewMode == .month {
                showingMonthPicker = true
              }
            } label: {
              Label(
                viewMode == .week ? "Select Week..." : "Select Month...",
                systemImage: isSpecificFilter ? "checkmark" : "calendar.view.day"
              )
            }

            Divider()

            // All sessions option
            Button {
              selectedFilter = .allSessions
              clearDaySelection()
            } label: {
              Label(
                "All Sessions",
                systemImage: selectedFilter == .allSessions ? "checkmark" : "list.bullet")
            }
          } label: {
            HStack(spacing: 4) {
              Image(systemName: filterMenuIcon)
              Text(filterMenuTitle)
                .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.primary)
          }
        }
      }
      .sheet(isPresented: $showingWeekPicker) {
        InsightsWeekPickerView(selectedDate: weeklyViewModel.selectedDate) { date in
          selectedFilter = .specificWeek
          weeklyViewModel.setWeek(for: date)
          clearDaySelection()
        }
        .presentationDetents([.medium, .large])
      }
      .sheet(isPresented: $showingMonthPicker) {
        InsightsMonthPickerView(selectedDate: monthlyViewModel.selectedDate) { date in
          selectedFilter = .specificMonth
          monthlyViewModel.setMonth(for: date)
          clearDaySelection()
        }
        .presentationDetents([.medium, .large])
      }
    }
    .task {
      await applyInitialState()
      updateInsightsDateRange()
    }
    .onChange(of: selectedFilter) { _, _ in
      updateInsightsDateRange()
    }
    .onChange(of: weeklyViewModel.selectedDate) { _, _ in
      updateInsightsDateRange()
    }
    .onChange(of: monthlyViewModel.selectedDate) { _, _ in
      updateInsightsDateRange()
    }
  }

  /// Scopes the Summary section's totals to whatever period is currently
  /// selected — the whole point of choosing "This Week" vs "All Sessions".
  private func updateInsightsDateRange() {
    switch selectedFilter {
    case .allSessions:
      profileInsightsViewModel.setDateRange(start: nil, end: nil)
    case .thisWeek, .lastWeek, .specificWeek:
      profileInsightsViewModel.setDateRange(start: weekStart, end: weekEndExclusive)
    case .thisMonth, .lastMonth, .specificMonth:
      profileInsightsViewModel.setDateRange(start: monthStart, end: monthEndExclusive)
    }
  }

  private func applyInitialState() async {
    guard !hasAppliedInitialState,
      let viewMode = initialViewMode,
      let date = initialSelectedDate
    else { return }

    hasAppliedInitialState = true

    switch viewMode {
    case .week:
      selectedFilter = .specificWeek
      weeklyViewModel.setWeek(for: date)
      // Wait a moment for the view model to update
      try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
      // Find and select the matching day
      if let matchingDay = weeklyViewModel.weeklySummary.days.first(where: {
        Calendar.current.isDate($0.date, inSameDayAs: date)
      }) {
        selectedWeekDay = matchingDay
      }
    case .month:
      selectedFilter = .specificMonth
      monthlyViewModel.setMonth(for: date)
      // Wait a moment for the view model to update
      try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
      // Find and select the matching day
      if let matchingDay = monthlyViewModel.monthlySummary.days.first(where: {
        Calendar.current.isDate($0.date, inSameDayAs: date)
      }) {
        selectedMonthDay = matchingDay
      }
    case .allSessions:
      selectedFilter = .allSessions
    }
  }

  private var filterMenuIcon: String {
    switch selectedFilter {
    case .thisWeek:
      return "calendar.day.timeline.left"
    case .lastWeek:
      return "calendar.day.timeline.right"
    case .thisMonth:
      return "calendar"
    case .lastMonth:
      return "arrow.left"
    case .specificWeek, .specificMonth:
      return "calendar.view.day"
    case .allSessions:
      return "list.bullet"
    }
  }

  private var filterMenuTitle: String {
    switch selectedFilter {
    case .thisWeek:
      return String(localized: "This Week")
    case .lastWeek:
      return String(localized: "Last Week")
    case .thisMonth:
      return String(localized: "This Month")
    case .lastMonth:
      return String(localized: "Last Month")
    case .specificWeek:
      return DateFormatters.formatWeekRange(
        start: weekSummary.weekStartDate, end: weekSummary.weekEndDate)
    case .specificMonth:
      return DateFormatters.formatMonthRange(
        start: monthSummary.monthStartDate, end: monthSummary.monthEndDate)
    case .allSessions:
      return String(localized: "All Sessions")
    }
  }

  private func clearDaySelection() {
    selectedWeekDay = nil
    selectedMonthDay = nil
  }
}

#Preview {
  struct PreviewWrapper: View {
    let container: ModelContainer
    let profile: BlockedProfiles

    init() {
      do {
        container = try ModelContainer(for: BlockedProfiles.self, BlockedProfileSession.self)
      } catch {
        fatalError("Failed to create preview container: \(error)")
      }

      let context = container.mainContext
      let profile = BlockedProfiles(name: "Work Focus")
      context.insert(profile)

      let calendar = Calendar.current
      let weekStart = WeeklySessionAggregator.startOfWeek(for: Date(), calendar: calendar)

      for dayOffset in 0..<6 {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart)!
        let session = BlockedProfileSession(
          tag: "Focus Block \(dayOffset + 1)", blockedProfile: profile)
        session.startTime = calendar.date(byAdding: .hour, value: 9 + dayOffset, to: day)!
        session.endTime = calendar.date(
          byAdding: .minute, value: 50 + dayOffset * 5, to: session.startTime)!
        context.insert(session)
      }

      self.profile = profile
    }

    var body: some View {
      ProfileInsightsView(profile: profile)
        .environmentObject(ThemeManager.shared)
        .modelContainer(container)
    }
  }

  return PreviewWrapper()
}
