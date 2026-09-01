import SwiftUI

struct AppIconPicker: View {
  let selectionColor: Color

  @State private var selectedIconName = UIApplication.shared.alternateIconName
  @State private var isChangingIcon = false
  @State private var showError = false
  @State private var errorMessage = ""

  private let columns = Array(
    repeating: GridItem(.flexible(), spacing: 12),
    count: AppIconOption.allCases.count
  )

  var body: some View {
    Section("App Icon") {
      LazyVGrid(columns: columns, spacing: 12) {
        ForEach(AppIconOption.allCases) { icon in
          Button {
            select(icon)
          } label: {
            VStack(spacing: 8) {
              Image(icon.previewAssetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                  RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                      isSelected(icon) ? selectionColor : .clear,
                      lineWidth: 3
                    )
                }
                .overlay(alignment: .topTrailing) {
                  if isSelected(icon) {
                    Image(systemName: "checkmark.circle.fill")
                      .symbolRenderingMode(.palette)
                      .foregroundStyle(.white, selectionColor)
                      .background(Circle().fill(.background))
                      .offset(x: 6, y: -6)
                  }
                }

              Text(icon.displayName)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .disabled(isChangingIcon || isSelected(icon))
          .accessibilityLabel("Use the \(icon.displayName) app icon")
          .accessibilityAddTraits(isSelected(icon) ? .isSelected : [])
        }
      }
      .padding(.vertical, 8)

      if !UIApplication.shared.supportsAlternateIcons {
        Text("Alternate app icons are not available on this device.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .alert("Unable to Change App Icon", isPresented: $showError) {
      Button("OK") {}
    } message: {
      Text(errorMessage)
    }
    .onAppear {
      selectedIconName = UIApplication.shared.alternateIconName
    }
  }

  private func isSelected(_ icon: AppIconOption) -> Bool {
    selectedIconName == icon.alternateIconName
  }

  private func select(_ icon: AppIconOption) {
    guard UIApplication.shared.supportsAlternateIcons else {
      errorMessage = String(localized: "Alternate app icons are not available on this device.")
      showError = true
      return
    }

    isChangingIcon = true
    UIApplication.shared.setAlternateIconName(icon.alternateIconName) { error in
      Task { @MainActor in
        isChangingIcon = false

        if let error {
          errorMessage = error.localizedDescription
          showError = true
          selectedIconName = UIApplication.shared.alternateIconName
          return
        }

        selectedIconName = UIApplication.shared.alternateIconName
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      }
    }
  }
}

private enum AppIconOption: String, CaseIterable, Identifiable {
  case orange
  case lemon
  case lime
  case dark

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .orange: String(localized: "Orange")
    case .lemon: String(localized: "Lemon")
    case .lime: String(localized: "Lime")
    case .dark: String(localized: "Dark")
    }
  }

  var alternateIconName: String? {
    switch self {
    case .orange: nil
    case .lemon: "Ctrus-icon-Lemon"
    case .lime: "Ctrus-icon-Lime"
    case .dark: "Ctrus-icon-Dark"
    }
  }

  var previewAssetName: String {
    switch self {
    case .orange: "AppIconOrangePreview"
    case .lemon: "AppIconLemonPreview"
    case .lime: "AppIconLimePreview"
    case .dark: "AppIconDarkPreview"
    }
  }
}

#Preview {
  Form {
    AppIconPicker(selectionColor: .purple)
  }
}
