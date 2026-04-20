import Foundation
import Combine
import UIKit
import UserNotifications
import Supabase

@MainActor
final class PushNotificationService: NSObject, ObservableObject {
    static let shared = PushNotificationService()

    private var client: SupabaseClient { SupabaseService.shared.client }
    /// Last token we registered on this device. Kept so we can remove it from
    /// the database on sign-out without needing to reconstruct from bytes.
    private var lastRegisteredToken: String?

    private override init() { super.init() }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func saveTokenIfDriver(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        lastRegisteredToken = token
        Task {
            do {
                let userId = try await client.auth.session.user.id
                // Only save token if user is a driver
                struct ProfileRole: Decodable { let role: String }
                let profile: ProfileRole = try await client
                    .from("profiles")
                    .select("role")
                    .eq("id", value: userId)
                    .single()
                    .execute()
                    .value
                guard profile.role == "driver" || profile.role == "both" else { return }
                struct TokenRow: Encodable {
                    let user_id: UUID
                    let device_token: String
                }
                try await client
                    .from("push_tokens")
                    .upsert(TokenRow(user_id: userId, device_token: token))
                    .execute()
            } catch {
                print("PushNotificationService.saveTokenIfDriver error:", error)
            }
        }
    }

    /// Remove this device's token from the DB. Called on sign-out so the
    /// previous user doesn't keep getting job-offer pushes on this device.
    func clearToken() async {
        guard let token = lastRegisteredToken else { return }
        do {
            try await client
                .from("push_tokens")
                .delete()
                .eq("device_token", value: token)
                .execute()
        } catch {
            print("PushNotificationService.clearToken error:", error)
        }
        lastRegisteredToken = nil
    }
}
