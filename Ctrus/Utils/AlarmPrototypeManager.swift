import AVFoundation
import ActivityKit
import AlarmKit
import AudioToolbox
import SwiftUI

/// Debug-only test of AlarmKit for the Alarm mode (spec D9): rings a minute
/// from now, opens the app when slid away, and keeps the sound going in the
/// app until it's stopped by hand.
@available(iOS 26.0, *)
@MainActor
final class AlarmPrototypeManager: ObservableObject {
  static let shared = AlarmPrototypeManager()

  static let prototypeProfileId = "prototype"
  static let repeatSeconds: TimeInterval = 60
  static let repeatCount = 30

  enum Sound: String, CaseIterable, Identifiable {
    case standard
    case vibrate

    var id: String { rawValue }

    var title: String {
      switch self {
      case .standard: return "Alarme Ctrus (som do sistema)"
      case .vibrate: return "Só vibrar (.caf silencioso)"
      }
    }

    var alertSound: AlertConfiguration.AlertSound {
      switch self {
      case .standard: return .default
      case .vibrate: return .named("alarm_silence.caf")
      }
    }
  }

  @Published var sound: Sound = .standard
  @Published var withBackups = false
  @Published private(set) var isRinging = false
  @Published private(set) var status = ""
  @Published private(set) var limitResult: String?
  @Published private(set) var events: [String] = []

  private var alarmIds: [UUID] = []
  private var player: AVAudioPlayer?
  private var vibrationTimer: Timer?
  private var backupTimer: Timer?

  private init() {
    NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
    ) { _ in
      Task { @MainActor in AlarmPrototypeManager.shared.appLeftWhileRinging() }
    }
  }

  // MARK: - Scheduling

  func scheduleTestAlarm() async {
    guard await authorize() else { return }

    await cancelAll()
    let fireDate = Date().addingTimeInterval(Self.repeatSeconds)

    do {
      try await schedule(at: fireDate)
      if withBackups {
        try await scheduleBackups(after: fireDate)
      }
      status =
        "Marcado para \(fireDate.formatted(date: .omitted, time: .standard))"
        + (withBackups ? " + \(Self.repeatCount) de reserva" : "")
      log("Marcado (\(alarmIds.count) alarmes)")
    } catch {
      status = "Erro ao marcar: \(error)"
    }
  }

  func probeLimit() async {
    guard await authorize() else { return }

    limitResult = "A testar…"
    var ids: [UUID] = []
    var stoppedBy: String?
    let base = Date().addingTimeInterval(365 * 24 * 60 * 60)

    for index in 0..<200 {
      let id = UUID()
      do {
        _ = try await AlarmManager.shared.schedule(
          id: id,
          configuration: configuration(at: base.addingTimeInterval(Double(index) * 60)))
        ids.append(id)
      } catch AlarmManager.AlarmError.maximumLimitReached {
        stoppedBy = "maximumLimitReached"
        break
      } catch {
        stoppedBy = "\(error)"
        break
      }
    }

    for id in ids {
      try? AlarmManager.shared.cancel(id: id)
    }

    let existing = (try? AlarmManager.shared.alarms.count) ?? 0
    if let stoppedBy {
      limitResult = "Aceitou \(ids.count) (+\(existing) já marcados), parou com: \(stoppedBy)"
    } else {
      limitResult = "Aceitou os \(ids.count) que tentei, sem limite"
    }
  }

  func cancelAll() async {
    for id in alarmIds {
      try? AlarmManager.shared.cancel(id: id)
    }
    alarmIds = []
  }

  private func authorize() async -> Bool {
    switch AlarmManager.shared.authorizationState {
    case .authorized:
      return true
    case .denied:
      status = "Alarmes recusados nas Definições"
      return false
    case .notDetermined:
      let state = try? await AlarmManager.shared.requestAuthorization()
      if state != .authorized {
        status = "Alarmes recusados"
      }
      return state == .authorized
    @unknown default:
      return false
    }
  }

  private func schedule(at date: Date) async throws {
    let id = UUID()
    _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration(at: date))
    alarmIds.append(id)
  }

  private func scheduleBackups(after date: Date) async throws {
    for index in 1...Self.repeatCount {
      try await schedule(at: date.addingTimeInterval(Double(index) * Self.repeatSeconds))
    }
  }

  private func configuration(at date: Date) -> AlarmManager.AlarmConfiguration<CtrusAlarmMetadata> {
    let alert: AlarmPresentation.Alert
    if #available(iOS 26.1, *) {
      alert = AlarmPresentation.Alert(title: "Teste Ctrus")
    } else {
      alert = AlarmPresentation.Alert(
        title: "Teste Ctrus",
        stopButton: AlarmButton(text: "Abrir", textColor: .white, systemImageName: "lock.open")
      )
    }

    let attributes = AlarmAttributes(
      presentation: AlarmPresentation(alert: alert),
      metadata: CtrusAlarmMetadata(profileId: nil, profileName: "Teste Ctrus"),
      tintColor: ThemeManager.shared.themeColor
    )

    return .alarm(
      schedule: .fixed(date),
      attributes: attributes,
      stopIntent: OpenAlarmProfileIntent(profileId: Self.prototypeProfileId),
      sound: sound.alertSound
    )
  }

  // MARK: - Ringing in the app

  func alarmOpenedApp(profileId: String) {
    log("Deslizado: a app abriu (\(UIApplication.shared.applicationState.label))")
    startRinging()
  }

  func stopRinging() {
    stopSound()
    log("Parado à mão")

    Task { await cancelAll() }
  }

  // The in-app sound can't outlive the app, so the system alarm takes over
  // straight away. Leaving the app to force-quit it passes through here too.
  private func appLeftWhileRinging() {
    guard isRinging else { return }
    stopSound()

    let backgroundTask = UIApplication.shared.beginBackgroundTask()
    Task {
      await cancelAll()
      let fireDate = Date().addingTimeInterval(1)
      do {
        try await schedule(at: fireDate)
        if withBackups {
          try await scheduleBackups(after: fireDate)
        }
        log("Saiu da app: o alarme volta a tocar já")
      } catch {
        log("Erro ao voltar a marcar: \(error)")
      }
      UIApplication.shared.endBackgroundTask(backgroundTask)
    }
  }

  private func stopSound() {
    player?.stop()
    player = nil
    vibrationTimer?.invalidate()
    vibrationTimer = nil
    backupTimer?.invalidate()
    backupTimer = nil
    isRinging = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func startRinging() {
    guard !isRinging else { return }
    isRinging = true

    do {
      try AVAudioSession.sharedInstance().setCategory(.playback)
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      log("AVAudioSession falhou: \(error)")
    }

    switch sound {
    case .standard:
      if let url = Bundle.main.url(forResource: "alarm_beep", withExtension: "caf") {
        player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1
        player?.play()
      }
    case .vibrate:
      vibrationTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
      }
      AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    // While the app is open the backups are pushed forward, so they only ring
    // if the app is closed without stopping it.
    if withBackups {
      backupTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
        Task { @MainActor in await AlarmPrototypeManager.shared.pushBackupsForward() }
      }
      Task { await pushBackupsForward() }
    }
  }

  private func pushBackupsForward() async {
    guard isRinging else { return }
    await cancelAll()
    do {
      try await scheduleBackups(after: Date())
      log("Reservas adiadas para daqui a \(Int(Self.repeatSeconds)) s")
    } catch {
      log("Erro ao adiar reservas: \(error)")
    }
  }

  private func log(_ message: String) {
    let time = Date().formatted(date: .omitted, time: .standard)
    events.insert("\(time) · \(message)", at: 0)
  }
}

extension UIApplication.State {
  fileprivate var label: String {
    switch self {
    case .active: return "ativa"
    case .inactive: return "inativa"
    case .background: return "em segundo plano"
    @unknown default: return "?"
    }
  }
}
