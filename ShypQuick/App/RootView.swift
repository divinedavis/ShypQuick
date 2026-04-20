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
                    .tabItem { Label("Deliver", systemImage: "car.fill") }
                ScheduledJobsView()
                    .tabItem { Label("Scheduled", systemImage: "calendar.badge.clock") }
            case .customer:
                CustomerHomeView(profile: profile)
                    .tabItem { Label("Send", systemImage: "shippingbox.fill") }
                MyScheduledView()
                    .tabItem { Label("Scheduled", systemImage: "calendar.badge.clock") }
            case .both:
                CustomerHomeView(profile: profile)
                    .tabItem { Label("Send", systemImage: "shippingbox.fill") }
                DriverHomeView()
                    .tabItem { Label("Deliver", systemImage: "car.fill") }
                MyScheduledView()
                    .tabItem { Label("Scheduled", systemImage: "calendar.badge.clock") }
            }

            HistoryView(profile: profile)
                .tabItem { Label("History", systemImage: "clock.fill") }

            ProfileView(profile: profile)
                .tabItem { Label("Profile", systemImage: "person.fill") }
        }
    }
}
