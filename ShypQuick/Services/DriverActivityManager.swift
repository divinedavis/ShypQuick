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
    private var timerTask: Task<Void, Never>?

    private init() {}

    func startOnlineActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // If already running, don't stack a second timer.
        guard currentActivity == nil else { return }

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
        timerTask?.cancel()
        timerTask = nil
        let activity = currentActivity
        currentActivity = nil
        Task {
            let state = DriverActivityAttributes.ContentState(
                status: "Offline",
                minutesOnline: 0
            )
            await activity?.end(
                .init(state: state, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            var minutes = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if Task.isCancelled { return }
                minutes += 1
                guard let self, let activity = self.currentActivity else { return }
                let state = DriverActivityAttributes.ContentState(
                    status: "Online",
                    minutesOnline: minutes
                )
                await activity.update(.init(state: state, staleDate: nil))
            }
        }
    }
}
