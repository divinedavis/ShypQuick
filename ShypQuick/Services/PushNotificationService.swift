import Foundation
import Combine
import UIKit
import UserNotifications
import Supabase

@MainActor
final class PushNotificationService: NSObject, ObservableObject {
    static let shared = PushNotificationService()

    private var client: SupabaseClient { SupabaseService.shared.client }

    private override init() { super.init() }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func saveToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task {
            do {
                let userId = try await client.auth.session.user.id
                struct TokenRow: Encodable {
                    let user_id: UUID
                    let device_token: String
                }
                try await client
                    .from("push_tokens")
                    .upsert(TokenRow(user_id: userId, device_token: token))
                    .execute()
            } catch { }
        }
    }
}
