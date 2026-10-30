import SwiftUI

@available(iOS 26.0, *)
struct AlarmPrototypeCard: View {
  @ObservedObject private var manager = AlarmPrototypeManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Picker("Som", selection: $manager.sound) {
        ForEach(AlarmPrototypeManager.Sound.allCases) { sound in
          Text(sound.title).tag(sound)
        }
      }
      .pickerStyle(.inline)

      Toggle(
        "Com \(AlarmPrototypeManager.repeatCount) alarmes de reserva (de 60 em 60 s)",
        isOn: $manager.withBackups
      )
      .font(.subheadline)

      Button("Testar alarme daqui a 1 min") {
        Task { await manager.scheduleTestAlarm() }
      }
      .buttonStyle(.borderedProminent)

      Button("Cancelar alarmes de teste") {
        Task { await manager.cancelAll() }
      }
      .buttonStyle(.bordered)

      Button("Ver quantos alarmes o AlarmKit aceita") {
        Task { await manager.probeLimit() }
      }
      .buttonStyle(.bordered)

      if !manager.status.isEmpty {
        Text(manager.status).font(.caption)
      }

      if let limitResult = manager.limitResult {
        Text(limitResult).font(.caption)
      }

      ForEach(manager.events, id: \.self) { event in
        Text(event)
          .font(.caption2.monospaced())
          .foregroundStyle(.secondary)
      }
    }
  }
}

/// The test button that stops the in-app sound, over whatever screen the
/// alarm opened the app on.
@available(iOS 26.0, *)
private struct AlarmPrototypeOverlay: ViewModifier {
  @ObservedObject private var manager = AlarmPrototypeManager.shared

  func body(content: Content) -> some View {
    content.overlay(alignment: .bottom) {
      if manager.isRinging {
        Button {
          manager.stopRinging()
        } label: {
          Text("Parar som (teste)")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .padding(20)
      }
    }
  }
}

extension View {
  @ViewBuilder
  func alarmPrototypeOverlay() -> some View {
    if #available(iOS 26.0, *) {
      modifier(AlarmPrototypeOverlay())
    } else {
      self
    }
  }
}
