import SwiftUI

struct RootView: View {
    @EnvironmentObject var session: SessionStore

    var body: some View {
        switch session.state {
        case .loading:
            ProgressView("Loading…")
        case .signedOut:
            AuthView()
        case .signedIn(let profile):
            MainTabView(profile: profile)
        }
    }
}

struct MainTabView: View {
    let profile: Profile
    @State private var activeRole: UserRole

    init(profile: Profile) {
        self.profile = profile
        _activeRole = State(initialValue: profile.role == .driver ? .driver : .customer)
    }

    var body: some View {
        TabView {
            if activeRole == .customer {
                CustomerHomeView()
                    .tabItem { Label("Send", systemImage: "shippingbox.fill") }
            } else {
                DriverHomeView()
                    .tabItem { Label("Drive", systemImage: "car.fill") }
            }

            HistoryView()
                .tabItem { Label("History", systemImage: "clock.fill") }

            ProfileView(activeRole: $activeRole)
                .tabItem { Label("Profile", systemImage: "person.fill") }
        }
    }
}
