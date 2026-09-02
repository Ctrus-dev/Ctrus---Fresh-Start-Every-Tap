//
//  ProfileWidgetEntry.swift
//  CtrusWidget
//
//  Created by Ali Waseem on 2025-03-11.
//

import Foundation
import WidgetKit

// MARK: - Widget Entry Model
struct ProfileWidgetEntry: TimelineEntry {
  let date: Date
  let selectedProfileId: String?
  let profileName: String?
  let activeSession: SharedData.SessionSnapshot?
  let profileSnapshot: SharedData.ProfileSnapshot?
  let deepLinkURL: URL?
  let focusMessage: String
  let useProfileURL: Bool?

  var isSessionActive: Bool {
    if let active = activeSession {
      return active.endTime == nil
    } else {
      return false
    }
  }

  var isBreakActive: Bool {
    guard let session = activeSession else { return false }
    return session.breakStartTime != nil && session.breakEndTime == nil
  }

  // Mirrors SessionTimeCalculator.expectedEndTime's break branch, using the
  // lightweight session/profile snapshots available to the widget.
  var breakEndDate: Date? {
    guard isBreakActive,
      let session = activeSession,
      let breakStartTime = session.breakStartTime,
      let profile = profileSnapshot
    else {
      return nil
    }

    let totalAllowance = TimeInterval(profile.breakTimeInMinutes * 60)

    if profile.allowMultipleBreaks == true {
      let usedBefore = session.usedBreakDurationInSeconds ?? 0
      let remainingAtStart = max(0, totalAllowance - usedBefore)
      return breakStartTime.addingTimeInterval(remainingAtStart)
    }

    return breakStartTime.addingTimeInterval(totalAllowance)
  }

  var isPauseActive: Bool {
    guard let session = activeSession else { return false }
    return session.pauseStartTime != nil && session.pauseEndTime == nil
  }

  var sessionStartTime: Date? {
    return activeSession?.startTime
  }
}
