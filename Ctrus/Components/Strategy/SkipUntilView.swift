import SwiftUI
import UIKit

struct SkipUntilView: View {
  @EnvironmentObject var themeManager: ThemeManager
  @Environment(\.dismiss) private var dismiss

  let schedule: BlockedProfileSchedule
  // Shown here rather than by the screen underneath, which can't present an
  // alert while this sheet covers it.
  @Binding var errorMessage: String?
  let onSkip: (Date) -> Void

  static let maxDaysAhead = 30

  @State private var selectedDay: Date? = nil

  private var skippedSessionCount: Int {
    guard let selectedDay else { return 0 }
    return schedule.upcomingOccurrenceStarts(throughEndOf: selectedDay).count
  }

  private var availableRange: ClosedRange<Date> {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let lastDay = calendar.date(byAdding: .day, value: Self.maxDaysAhead, to: today) ?? today
    return today...lastDay
  }

  var body: some View {
    NavigationStack {
      content
        .navigationTitle(String(localized: "Skip until…"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button(action: { dismiss() }) {
              Image(systemName: "xmark")
            }
            .accessibilityLabel("Close")
          }
        }
    }
  }

  private var content: some View {
    VStack(spacing: 20) {
      SingleDayCalendar(
        selectedDay: $selectedDay,
        availableRange: availableRange,
        tintColor: UIColor(themeManager.themeColor)
      )
      .frame(maxWidth: .infinity)

      Divider()

      if let selectedDay {
        Text(summaryText(for: selectedDay))
          .font(.callout)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      ActionButton(
        title: String(localized: "Skip with Ctrus"),
        backgroundColor: themeManager.themeColor,
        isDisabled: skippedSessionCount == 0
      ) {
        guard let selectedDay else { return }
        onSkip(selectedDay)
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 24)
    .padding(.bottom, 24)
    .alert(
      String(localized: "Whoops"),
      isPresented: Binding(
        get: { errorMessage != nil },
        set: { isPresented in
          if !isPresented { errorMessage = nil }
        }
      )
    ) {
      Button("OK", role: .cancel) { errorMessage = nil }
    } message: {
      Text(errorMessage ?? "")
    }
  }

  private func summaryText(for day: Date) -> String {
    guard skippedSessionCount > 0 else {
      return String(localized: "There are no sessions on those days.")
    }

    let dayText = ScheduleSkipUtil.weekdayAndDayText(for: day)
    return String(localized: "Skips \(skippedSessionCount) sessions, until \(dayText).")
  }
}

// A graphical DatePicker always shows some day as chosen, but this sheet
// starts with none — UICalendarView's single-date selection can be empty, and
// it greys out the days outside the range on its own.
private struct SingleDayCalendar: UIViewRepresentable {
  @Binding var selectedDay: Date?
  let availableRange: ClosedRange<Date>
  let tintColor: UIColor

  func makeUIView(context: Context) -> UICalendarView {
    let calendarView = UICalendarView()
    calendarView.calendar = Calendar.current
    calendarView.locale = Locale.autoupdatingCurrent
    calendarView.availableDateRange = DateInterval(
      start: availableRange.lowerBound,
      end: Calendar.current.date(byAdding: .day, value: 1, to: availableRange.upperBound)?
        .addingTimeInterval(-1) ?? availableRange.upperBound
    )
    calendarView.tintColor = tintColor
    calendarView.selectionBehavior = UICalendarSelectionSingleDate(delegate: context.coordinator)
    calendarView.setContentHuggingPriority(.required, for: .vertical)
    calendarView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return calendarView
  }

  func updateUIView(_ uiView: UICalendarView, context: Context) {
    context.coordinator.parent = self
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  final class Coordinator: NSObject, UICalendarSelectionSingleDateDelegate {
    var parent: SingleDayCalendar

    init(parent: SingleDayCalendar) {
      self.parent = parent
    }

    func dateSelection(
      _ selection: UICalendarSelectionSingleDate,
      didSelectDate dateComponents: DateComponents?
    ) {
      parent.selectedDay = dateComponents.flatMap { Calendar.current.date(from: $0) }
    }
  }
}

#Preview {
  SkipUntilView(
    schedule: BlockedProfileSchedule(
      days: [.monday, .wednesday, .friday],
      startHour: 22,
      startMinute: 0,
      durationInHours: 2
    ),
    errorMessage: .constant(nil),
    onSkip: { _ in }
  )
  .environmentObject(ThemeManager.shared)
}
