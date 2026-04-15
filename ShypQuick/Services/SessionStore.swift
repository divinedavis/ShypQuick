import Foundation
import Combine
import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    enum State {
        case loading
        case signedOut
        case signedIn(Profile)
    }

    @Published var state: State = .loading

    func bootstrap() async {
        // TODO: Check Supabase session and load profile.
        // For now, start signed out.
        state = .signedOut
    }

    func signIn(email: String, password: String) async throws {
        // TODO: SupabaseService.shared.client.auth.signIn(...)
    }

    func signUp(email: String, password: String, fullName: String) async throws {
        // TODO: SupabaseService.shared.client.auth.signUp(...)
    }

    func signOut() async {
        state = .signedOut
    }
}
