import Foundation
import ActivityKit

struct DriverActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var status: String
        var minutesOnline: Int
    }
}

@MainActor
final class DriverActivityManager {
    static let shared = DriverActivityManager()
    private var currentActivity: Activity<DriverActivityAttributes>?

    private init() {}

    func startOnlineActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = DriverActivityAttributes()
        let state = DriverActivityAttributes.ContentState(
            status: "Online",
            minutesOnline: 0
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            startTimer()
        } catch {
            // Live Activities not supported
        }
    }

    func stopOnlineActivity() {
        Task {
            let state = DriverActivityAttributes.ContentState(
                status: "Offline",
                minutesOnline: 0
            )
            await currentActivity?.end(
                .init(state: state, staleDate: nil),
                dismissalPolicy: .immediate
            )
            currentActivity = nil
        }
    }

    private func startTimer() {
        Task {
            var minutes = 0
            while currentActivity != nil {
                try? await Task.sleep(for: .seconds(60))
                minutes += 1
                guard currentActivity != nil else { return }
                let state = DriverActivityAttributes.ContentState(
                    status: "Online",
                    minutesOnline: minutes
                )
                await currentActivity?.update(.init(state: state, staleDate: nil))
            }
        }
    }
}
