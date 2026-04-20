import ActivityKit
import WidgetKit
import SwiftUI

struct DriverActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var status: String
        var minutesOnline: Int
    }
}

struct ShypQuickLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DriverActivityAttributes.self) { context in
            // Lock Screen / Banner view
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.green)
                        .frame(width: 10, height: 10)
                    Text("SHYP Quick")
                        .font(.headline.bold())
                }
                Spacer()
                Text(context.state.status)
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)
                if context.state.minutesOnline > 0 {
                    Text("· \(context.state.minutesOnline)m")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.green)
                            .frame(width: 10, height: 10)
                        Text("SHYP Quick")
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.status)
                            .font(.subheadline.bold())
                            .foregroundStyle(.green)
                        if context.state.minutesOnline > 0 {
                            Text("\(context.state.minutesOnline) min")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Waiting for delivery requests")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                // Compact leading (left pill)
                Circle()
                    .fill(.green)
                    .frame(width: 12, height: 12)
            } compactTrailing: {
                // Compact trailing (right pill)
                Text(context.state.status)
                    .font(.caption2.bold())
                    .foregroundStyle(.green)
            } minimal: {
                // Minimal (just a dot when other activities are present)
                Circle()
                    .fill(.green)
                    .frame(width: 12, height: 12)
            }
        }
    }
}
