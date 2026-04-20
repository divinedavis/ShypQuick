import SwiftUI
import UserNotifications

@main
struct ShypQuickApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .task {
                    let usedAutoLogin = await autoLoginIfRequested()
                    if !usedAutoLogin {
                        await session.bootstrap()
                        PushNotificationService.shared.requestPermission()
                    }
                }
        }
    }

    /// Simulator-only shortcut: launch with
    ///   `-SHYP_AUTO_LOGIN_EMAIL foo@bar.com -SHYP_AUTO_LOGIN_PASSWORD pwd`
    /// to skip the auth screen and the push-permission prompt. Used for
    /// README screenshots. Stripped from Release builds.
    ///
    /// - Returns: `true` if auto-login ran (successfully or not) — caller
    ///   should skip the normal bootstrap/push-prompt path.
    @MainActor
    private func autoLoginIfRequested() async -> Bool {
        #if DEBUG && targetEnvironment(simulator)
        // `-KEY value` launch args land in UserDefaults automatically, which
        // makes them easy to pass via `xcrun simctl launch`.
        let defaults = UserDefaults.standard
        guard let email = defaults.string(forKey: "SHYP_AUTO_LOGIN_EMAIL"),
              let pwd = defaults.string(forKey: "SHYP_AUTO_LOGIN_PASSWORD"),
              !email.isEmpty, !pwd.isEmpty else { return false }
        do {
            try await session.signIn(email: email, password: pwd)
        } catch {
            print("auto-login failed:", error)
        }
        return true
        #else
        return false
        #endif
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushNotificationService.shared.saveTokenIfDriver(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Push not available (simulator, denied, etc.)
    }

    // Show notification as banner even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap — auto go online and fetch offer
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            DispatchService.shared.notificationTapped = true
            DispatchService.shared.startListening()
        }
        completionHandler()
    }
}
