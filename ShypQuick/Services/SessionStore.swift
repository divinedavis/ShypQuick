import Foundation
import Combine
import SwiftUI
import Supabase

@MainActor
final class SessionStore: ObservableObject {
    enum State {
        case loading
        case signedOut
        case signedIn(Profile)
    }

    @Published var state: State = .loading

    private var client: SupabaseClient { SupabaseService.shared.client }

    func bootstrap() async {
        do {
            let session = try await client.auth.session
            let profile = try await loadProfile(userId: session.user.id)
            state = .signedIn(profile)
        } catch {
            state = .signedOut
        }
    }

    func signIn(email: String, password: String) async throws {
        let session = try await client.auth.signIn(email: email, password: password)
        let profile = try await loadProfile(userId: session.user.id)
        state = .signedIn(profile)
    }

    func signUp(email: String, password: String, fullName: String, role: UserRole) async throws {
        let response = try await client.auth.signUp(
            email: email,
            password: password,
            data: [
                "full_name": .string(fullName),
                "role": .string(role.rawValue)
            ]
        )

        // If email confirmation is disabled, we get an active session back.
        if response.session != nil {
            let profile = try await loadProfile(userId: response.user.id)
            state = .signedIn(profile)
        } else {
            // Email confirmation required — user must click link before signing in.
            state = .signedOut
            throw AuthError.emailConfirmationRequired
        }
    }

    func updateHomeAddress(address: String, lat: Double, lng: Double) async throws {
        guard case .signedIn(var profile) = state else { return }
        struct HomeUpdate: Encodable {
            let home_address: String
            let home_lat: Double
            let home_lng: Double
        }
        try await client
            .from("profiles")
            .update(HomeUpdate(home_address: address, home_lat: lat, home_lng: lng))
            .eq("id", value: profile.id)
            .execute()
        profile.homeAddress = address
        profile.homeLat = lat
        profile.homeLng = lng
        state = .signedIn(profile)
    }

    func signOut() async {
        try? await client.auth.signOut()
        state = .signedOut
    }

    private func loadProfile(userId: UUID) async throws -> Profile {
        try await client
            .from("profiles")
            .select()
            .eq("id", value: userId)
            .single()
            .execute()
            .value
    }
}

enum AuthError: LocalizedError {
    case emailConfirmationRequired

    var errorDescription: String? {
        switch self {
        case .emailConfirmationRequired:
            return "Check your email and click the confirmation link to finish signing up."
        }
    }
}
