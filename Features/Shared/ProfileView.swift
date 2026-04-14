import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var session: SessionStore
    @Binding var activeRole: UserRole

    var body: some View {
        NavigationStack {
            List {
                Section("Role") {
                    Picker("Active role", selection: $activeRole) {
                        Text("Customer").tag(UserRole.customer)
                        Text("Driver").tag(UserRole.driver)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await session.signOut() }
                    }
                }
            }
            .navigationTitle("Profile")
        }
    }
}
