import ActivityKit
import SwiftUI
import WidgetKit

// Forge rest-timer Live Activity (lock screen + Dynamic Island).
//
// The Dart side (LiveActivityService) passes three values through the
// shared App Group (group.com.forge.app.forge):
//   exerciseName — the exercise the rest belongs to ("Squat")
//   nextSet      — "Set 2"
//   endsAtMillis — rest end, milliseconds since epoch
// The countdown is rendered by the system from endsAt (Text with a
// timer interval), so it keeps counting even when the app is
// backgrounded or killed.
//
// Adding the target is a manual Xcode step — see
// ios/LIVE_ACTIVITY_SETUP.md. Until it is added, the Dart calls
// fail silently and the notification shade + in-app timer cover iOS.

@main
struct ForgeLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    if #available(iOS 16.1, *) {
      ForgeRestActivity()
    }
  }
}

// The attributes type MUST be named exactly LiveActivitiesAppAttributes
// — the live_activities plugin looks it up by name. The content state
// is empty: all display data comes through the shared defaults.
struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
  public typealias LiveDeliveryData = ContentState
  public struct ContentState: Codable, Hashable {}
  var id = UUID()
}

extension LiveActivitiesAppAttributes {
  func prefixedKey(_ key: String) -> String {
    "\(id)_\(key)"
  }
}

private let sharedDefault = UserDefaults(suiteName: "group.com.forge.app.forge")!

// Forge colours.
private let forgeOrange = Color(red: 1.0, green: 0.42, blue: 0.0)
private let forgeText = Color(red: 0.949, green: 0.961, blue: 0.969)
private let forgeMuted = Color(red: 0.541, green: 0.592, blue: 0.639)

/// The three values the Dart side wrote for this activity.
private struct RestData {
  let exerciseName: String
  let nextSet: String
  let endsAt: Date
}

@available(iOS 16.1, *)
private func restData(
  from context: ActivityViewContext<LiveActivitiesAppAttributes>
) -> RestData {
  let exerciseName = sharedDefault.string(
    forKey: context.attributes.prefixedKey("exerciseName")
  ) ?? "Rest"
  let nextSet = sharedDefault.string(
    forKey: context.attributes.prefixedKey("nextSet")
  ) ?? "Set 1"
  let endsAt = Date(
    timeIntervalSince1970: sharedDefault.double(
      forKey: context.attributes.prefixedKey("endsAtMillis")
    ) / 1000
  )
  return RestData(exerciseName: exerciseName, nextSet: nextSet, endsAt: endsAt)
}

@available(iOS 16.1, *)
struct ForgeRestActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
      let data = restData(from: context)
      let restRange = Date.now...data.endsAt

      // Lock screen.
      ZStack {
        Color.black
        HStack(spacing: 12) {
          VStack(alignment: .leading, spacing: 2) {
            Text("FORGE · REST")
              .font(.caption2)
              .fontWeight(.bold)
              .foregroundColor(forgeOrange)
            Text(data.exerciseName)
              .font(.headline)
              .foregroundColor(forgeText)
              .lineLimit(1)
            Text("Next: \(data.nextSet)")
              .font(.subheadline)
              .foregroundColor(forgeMuted)
              .lineLimit(1)
          }
          Spacer()
          Text(timerInterval: restRange, countsDown: true)
            .font(.title2)
            .fontWeight(.bold)
            .monospacedDigit()
            .foregroundColor(forgeOrange)
        }
        .padding(.horizontal, 16)
      }
    } dynamicIsland: { context in
      let data = restData(from: context)
      let restRange = Date.now...data.endsAt

      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          VStack(alignment: .leading, spacing: 2) {
            Text(data.exerciseName)
              .font(.headline)
              .foregroundColor(forgeText)
              .lineLimit(1)
            Text("Next: \(data.nextSet)")
              .font(.subheadline)
              .foregroundColor(forgeMuted)
              .lineLimit(1)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(timerInterval: restRange, countsDown: true)
            .font(.title3)
            .fontWeight(.bold)
            .monospacedDigit()
            .foregroundColor(forgeOrange)
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text("FORGE · REST")
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(forgeOrange)
        }
      } compactLeading: {
        Text(timerInterval: restRange, countsDown: true)
          .font(.caption)
          .fontWeight(.bold)
          .monospacedDigit()
          .foregroundColor(forgeOrange)
      } compactTrailing: {
        Text(data.nextSet)
          .font(.caption)
          .fontWeight(.bold)
          .foregroundColor(forgeText)
      } minimal: {
        Text(timerInterval: restRange, countsDown: true)
          .font(.caption2)
          .fontWeight(.bold)
          .monospacedDigit()
          .foregroundColor(forgeOrange)
      }
    }
  }
}
