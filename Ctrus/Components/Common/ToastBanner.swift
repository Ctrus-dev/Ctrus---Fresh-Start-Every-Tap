import SwiftUI

/// A short confirmation that slides in at the bottom and goes away by itself.
struct ToastBanner: ViewModifier {
  @Binding var message: String?

  var displayDuration: TimeInterval = 3

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .bottom) {
        if let message {
          Text(message)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.85), in: Capsule())
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: message) {
              try? await Task.sleep(for: .seconds(displayDuration))
              withAnimation(.easeInOut(duration: 0.25)) {
                self.message = nil
              }
            }
        }
      }
      .animation(.easeInOut(duration: 0.25), value: message)
  }
}

extension View {
  func toastBanner(message: Binding<String?>) -> some View {
    modifier(ToastBanner(message: message))
  }
}

#Preview {
  Color.white
    .toastBanner(message: .constant("Done. The schedule is back on Nov 9."))
}
