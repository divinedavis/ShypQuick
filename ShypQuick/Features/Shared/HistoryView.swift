import SwiftUI
import Supabase

struct CompletedJob: Codable, Identifiable {
    let id: UUID
    let pickupAddress: String
    let dropoffAddress: String
    let totalCents: Int
    let categoryTitle: String
    let categoryIcon: String
    let status: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case pickupAddress = "pickup_address"
        case dropoffAddress = "dropoff_address"
        case totalCents = "total_cents"
        case categoryTitle = "category_title"
        case categoryIcon = "category_icon"
        case status
        case createdAt = "created_at"
    }
}

struct HistoryView: View {
    @State private var jobs: [CompletedJob] = []
    @State private var isLoading = true

    private var client: SupabaseClient { SupabaseService.shared.client }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                } else if jobs.isEmpty {
                    ContentUnavailableView(
                        "No deliveries yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Your completed deliveries will appear here.")
                    )
                } else {
                    List(jobs) { job in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: job.categoryIcon).foregroundStyle(.tint)
                                Text(job.categoryTitle).font(.headline)
                                Spacer()
                                let earnings = Int(Double(job.totalCents) * 0.70)
                                Text(PricingService.Quote.format(earnings))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.green)
                            }
                            Label(job.pickupAddress, systemImage: "circle.fill")
                                .font(.subheadline)
                            Label(job.dropoffAddress, systemImage: "mappin.circle.fill")
                                .font(.subheadline)
                            if let date = job.createdAt {
                                Text(date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("History")
            .task { await loadHistory() }
            .refreshable { await loadHistory() }
        }
    }

    private func loadHistory() async {
        do {
            let userId = try await client.auth.session.user.id
            jobs = try await client
                .from("job_offers")
                .select()
                .eq("status", value: "accepted")
                .eq("driver_id", value: userId)
                .order("created_at", ascending: false)
                .execute()
                .value
            isLoading = false
        } catch {
            isLoading = false
        }
    }
}
