import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var session: SessionStore
    let profile: Profile

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    LabeledContent("Name", value: profile.fullName ?? "—")
                    LabeledContent("Role") {
                        Label(roleLabel, systemImage: roleIcon)
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.tint)
                    }
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

    private var roleLabel: String {
        switch profile.role {
        case .customer: return "Customer"
        case .driver:   return "Driver"
        case .both:     return "Customer & Driver"
        }
    }

    private var roleIcon: String {
        switch profile.role {
        case .customer: return "shippingbox.fill"
        case .driver:   return "car.fill"
        case .both:     return "person.2.fill"
        }
    }
}
