import AlarmKit
import SwiftUI
import WidgetKit

// How an Alarm mode alarm looks on the lock screen and in the Dynamic Island,
// in the same style as the session's Live Activity.
@available(iOS 26.0, *)
struct CtrusAlarmLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: AlarmAttributes<CtrusAlarmMetadata>.self) { context in
      HStack(alignment: .center, spacing: 16) {
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 4) {
            Text("Ctrus")
              .font(.headline)
              .fontWeight(.bold)
              .foregroundColor(.primary)
            logo(size: 20)
          }

          Text(context.attributes.metadata?.profileName ?? "")
            .font(.subheadline)
            .foregroundColor(.primary)
        }

        Spacer()

        Image(systemName: "alarm.fill")
          .font(.title)
          .foregroundStyle(context.attributes.tintColor)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)

    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          logo(size: 30)
        }

        DynamicIslandExpandedRegion(.center) {
          Text(context.attributes.metadata?.profileName ?? "Ctrus")
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .lineLimit(1)
        }

        DynamicIslandExpandedRegion(.trailing) {
          Image(systemName: "alarm.fill")
            .font(.title2)
            .foregroundStyle(context.attributes.tintColor)
        }
      } compactLeading: {
        logo(size: 24)
      } compactTrailing: {
        Image(systemName: "alarm.fill")
          .foregroundStyle(context.attributes.tintColor)
      } minimal: {
        Image(systemName: "alarm.fill")
          .foregroundStyle(context.attributes.tintColor)
      }
    }
  }

  private func logo(size: CGFloat) -> some View {
    Image(systemName: "lock.fill")
      .resizable()
      .scaledToFit()
      .frame(width: size, height: size)
  }
}
