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

    var body: some View {
        TabView {
            switch profile.role {
            case .driver:
                DriverHomeView()
                    .tabItem { Label("Drive", systemImage: "car.fill") }
            case .customer, .both:
                CustomerHomeView(profile: profile)
                    .tabItem { Label("Send", systemImage: "shippingbox.fill") }
            }

            HistoryView()
                .tabItem { Label("History", systemImage: "clock.fill") }

            ProfileView(profile: profile)
                .tabItem { Label("Profile", systemImage: "person.fill") }
        }
    }
}
