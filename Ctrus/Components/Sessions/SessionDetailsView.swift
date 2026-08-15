import SwiftData
import SwiftUI

struct SessionDetailsView: View {
  @Environment(\.dismiss) private var dismiss

  let session: BlockedProfileSession

  var body: some View {
    NavigationStack {
      Form {
        SessionInfoSection(session: session)
        TimingSection(session: session)

        if session.breakStartTime != nil && session.breakEndTime != nil {
          BreakSection(session: session)
        }

        if session.pauseStartTime != nil && session.pauseEndTime != nil {
          PauseSection(session: session)
        }
      }
      .navigationTitle("Session Details")
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
}

// MARK: - Session Info Section

private struct SessionInfoSection: View {
  let session: BlockedProfileSession

  var body: some View {
    Section("Session Info") {
      InfoRow(label: String(localized: "Tag"), value: session.tag)
      InfoRow(label: String(localized: "Profile"), value: session.blockedProfile.name)
      InfoRow(
        label: String(localized: "Force Started"),
        value: session.forceStarted ? String(localized: "Yes") : String(localized: "No"))
    }
  }
}

// MARK: - Timing Section

private struct TimingSection: View {
  let session: BlockedProfileSession

  var body: some View {
    Section("Timing") {
      InfoRow(
        label: String(localized: "Started"),
        value: DateFormatters.formatDate(session.startTime)
      )

      if let endTime = session.endTime {
        InfoRow(
          label: String(localized: "Ended"),
          value: DateFormatters.formatDate(endTime)
        )
      } else {
        InfoRow(label: String(localized: "Ended"), value: String(localized: "In Progress"))
          .foregroundStyle(.secondary)
      }

      InfoRow(
        label: String(localized: "Duration"),
        value: DateFormatters.formatDurationHoursMinutes(session.duration)
      )
    }
  }
}

// MARK: - Break Section

private struct BreakSection: View {
  let session: BlockedProfileSession

  var breakDuration: TimeInterval? {
    guard let breakStartTime = session.breakStartTime,
      let breakEndTime = session.breakEndTime
    else {
      return nil
    }
    return breakEndTime.timeIntervalSince(breakStartTime)
  }

  var body: some View {
    Section("Break") {
      if let breakStartTime = session.breakStartTime {
        InfoRow(
          label: String(localized: "Started"),
          value: DateFormatters.formatDate(breakStartTime)
        )
      }

      if let breakEndTime = session.breakEndTime {
        InfoRow(
          label: String(localized: "Ended"),
          value: DateFormatters.formatDate(breakEndTime)
        )
      }

      if let breakDuration = breakDuration {
        InfoRow(
          label: String(localized: "Duration"),
          value: String(localized: "\(Int(breakDuration / 60))m")
        )
      }
    }
  }
}

// MARK: - Pause Section

private struct PauseSection: View {
  let session: BlockedProfileSession

  var pauseDuration: TimeInterval? {
    guard let pauseStartTime = session.pauseStartTime,
      let pauseEndTime = session.pauseEndTime
    else {
      return nil
    }
    return pauseEndTime.timeIntervalSince(pauseStartTime)
  }

  var body: some View {
    Section("Pause") {
      if let pauseStartTime = session.pauseStartTime {
        InfoRow(
          label: String(localized: "Started"),
          value: DateFormatters.formatDate(pauseStartTime)
        )
      }

      if let pauseEndTime = session.pauseEndTime {
        InfoRow(
          label: String(localized: "Ended"),
          value: DateFormatters.formatDate(pauseEndTime)
        )
      }

      if let pauseDuration = pauseDuration {
        InfoRow(
          label: String(localized: "Duration"),
          value: DateFormatters.formatDurationShort(pauseDuration)
        )
      }
    }
  }
}

// MARK: - Info Row Component

private struct InfoRow: View {
  let label: String
  let value: String

  var body: some View {
    HStack {
      Text(label)
        .foregroundStyle(.primary)
      Spacer()
      Text(value)
        .foregroundStyle(.secondary)
    }
  }
}

// MARK: - Previews

#Preview("Active Session") {
  struct PreviewWrapper: View {
    let profile: BlockedProfiles
    let session: BlockedProfileSession

    init() {
      let profile = BlockedProfiles(name: "Work Focus")
      let session = BlockedProfileSession(
        tag: "Morning Session",
        blockedProfile: profile,
        forceStarted: false
      )
      self.profile = profile
      self.session = session
    }

    var body: some View {
      SessionDetailsView(session: session)
    }
  }

  return PreviewWrapper()
    .modelContainer(for: [BlockedProfiles.self, BlockedProfileSession.self])
}

#Preview("Active Session with Break") {
  struct PreviewWrapper: View {
    let profile: BlockedProfiles
    let session: BlockedProfileSession

    init() {
      let profile = BlockedProfiles(
        name: "Deep Work",
        enableBreaks: true
      )
      let session = BlockedProfileSession(
        tag: "Focus Time",
        blockedProfile: profile,
        forceStarted: false
      )
      session.startBreak()
      self.profile = profile
      self.session = session
    }

    var body: some View {
      SessionDetailsView(session: session)
    }
  }

  return PreviewWrapper()
    .modelContainer(for: [BlockedProfiles.self, BlockedProfileSession.self])
}

#Preview("Completed Session with Break and Pause") {
  struct PreviewWrapper: View {
    let profile: BlockedProfiles
    let session: BlockedProfileSession

    init() {
      let profile = BlockedProfiles(
        name: "Study Session",
        enableBreaks: true
      )
      let session = BlockedProfileSession(
        tag: "Exam Prep",
        blockedProfile: profile,
        forceStarted: true
      )

      // Simulate a completed session
      session.endTime = Date().addingTimeInterval(-3600)

      // Add a break
      session.breakStartTime = Date().addingTimeInterval(-2700)
      session.breakEndTime = Date().addingTimeInterval(-2400)

      // Add a pause
      session.pauseStartTime = Date().addingTimeInterval(-1800)
      session.pauseEndTime = Date().addingTimeInterval(-1500)

      self.profile = profile
      self.session = session
    }

    var body: some View {
      SessionDetailsView(session: session)
    }
  }

  return PreviewWrapper()
    .modelContainer(for: [BlockedProfiles.self, BlockedProfileSession.self])
}
