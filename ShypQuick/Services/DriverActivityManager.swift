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

    private init() {
        // Clean up any lingering activity from a previous app launch where
        // the driver went offline while the app was backgrounded/killed.
        // Without this, the Dynamic Island keeps showing "Online" from the
        // old process even though we have no reference to it anymore.
        Task { await cleanupOrphanedActivities() }
    }

    func startOnlineActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // If we lost our reference but a system activity is still showing,
        // kill it before starting a fresh one.
        Task { await cleanupOrphanedActivities() }
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
            // End our tracked activity first.
            await activity?.end(nil, dismissalPolicy: .immediate)
            // Defensive: also end any other DriverActivity still in the
            // system UI that we may have lost track of.
            await cleanupOrphanedActivities()
        }
    }

    /// End every existing DriverActivityAttributes activity. Used on startup
    /// and on stop to guarantee no stale "Online" banner survives.
    private func cleanupOrphanedActivities() async {
        for activity in Activity<DriverActivityAttributes>.activities {
            if activity.id == currentActivity?.id { continue }
            await activity.end(nil, dismissalPolicy: .immediate)
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
