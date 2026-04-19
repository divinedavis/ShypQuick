import SwiftUI
import Supabase

struct CompletedJob: Codable, Identifiable {
    let id: UUID
    let customerId: UUID
    let pickupAddress: String
    let dropoffAddress: String
    let totalCents: Int
    let categoryTitle: String
    let categoryIcon: String
    let status: String
    let driverId: UUID?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case customerId = "customer_id"
        case pickupAddress = "pickup_address"
        case dropoffAddress = "dropoff_address"
        case totalCents = "total_cents"
        case categoryTitle = "category_title"
        case categoryIcon = "category_icon"
        case status
        case driverId = "driver_id"
        case createdAt = "created_at"
    }
}

struct HistoryView: View {
    let profile: Profile
    @State private var jobs: [CompletedJob] = []
    @State private var isLoading = true

    private var client: SupabaseClient { SupabaseService.shared.client }
    private var isDriver: Bool { profile.role == .driver }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                } else if jobs.isEmpty {
                    ContentUnavailableView(
                        "No deliveries yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text(isDriver
                            ? "Jobs you complete will appear here."
                            : "Deliveries you request will appear here.")
                    )
                } else {
                    List(jobs) { job in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: job.categoryIcon).foregroundStyle(.tint)
                                Text(job.categoryTitle).font(.headline)
                                Spacer()
                                if isDriver {
                                    let earnings = Int(Double(job.totalCents) * 0.70)
                                    Text(PricingService.Quote.format(earnings))
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.green)
                                } else {
                                    Text(PricingService.Quote.format(job.totalCents))
                                        .font(.subheadline.bold())
                                }
                            }
                            Label(job.pickupAddress, systemImage: "circle.fill")
                                .font(.subheadline)
                            Label(job.dropoffAddress, systemImage: "mappin.circle.fill")
                                .font(.subheadline)

                            HStack {
                                if let date = job.createdAt {
                                    Text(date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !isDriver {
                                    let statusInfo = customerStatus(job)
                                    Label(statusInfo.label, systemImage: statusInfo.icon)
                                        .font(.caption.bold())
                                        .foregroundStyle(statusInfo.color)
                                }
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

    private func customerStatus(_ job: CompletedJob) -> (label: String, icon: String, color: Color) {
        switch job.status {
        case "delivered":
            return ("Delivered", "checkmark.seal.fill", .green)
        case "accepted":
            return ("In progress", "arrow.triangle.swap", .blue)
        case "expired", "declined":
            return ("Expired", "xmark.circle.fill", .secondary)
        default:
            return ("Pending", "clock.fill", .orange)
        }
    }

    private func loadHistory() async {
        do {
            let userId = try await client.auth.session.user.id
            if isDriver {
                jobs = try await client
                    .from("job_offers")
                    .select()
                    .in("status", values: ["accepted", "delivered"])
                    .eq("driver_id", value: userId)
                    .order("created_at", ascending: false)
                    .execute()
                    .value
            } else {
                jobs = try await client
                    .from("job_offers")
                    .select()
                    .eq("customer_id", value: userId)
                    .order("created_at", ascending: false)
                    .execute()
                    .value
            }
            isLoading = false
        } catch {
            isLoading = false
        }
    }
}
