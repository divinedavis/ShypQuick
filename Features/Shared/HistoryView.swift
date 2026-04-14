import SwiftUI

struct HistoryView: View {
    var body: some View {
        NavigationStack {
            List {
                ContentUnavailableView(
                    "No deliveries yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Your past deliveries will appear here.")
                )
            }
            .navigationTitle("History")
        }
    }
}
