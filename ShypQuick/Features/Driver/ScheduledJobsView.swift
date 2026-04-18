import SwiftUI

struct ScheduledJobsView: View {
    @StateObject private var schedule = ScheduleService.shared

    private var available: [ScheduledDelivery] {
        schedule.deliveries.filter { !$0.isAccepted }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    private var accepted: [ScheduledDelivery] {
        schedule.deliveries.filter { $0.isAccepted }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if schedule.deliveries.isEmpty {
                    ContentUnavailableView(
                        "No scheduled deliveries",
                        systemImage: "calendar.badge.clock",
                        description: Text("Scheduled jobs from customers will appear here.")
                    )
                } else {
                    List {
                        if !available.isEmpty {
                            Section("Available") {
                                ForEach(available) { delivery in
                                    jobRow(delivery, showAccept: true)
                                }
                            }
                        }
                        if !accepted.isEmpty {
                            Section("My accepted jobs") {
                                ForEach(accepted) { delivery in
                                    jobRow(delivery, showAccept: false)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Scheduled jobs")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func jobRow(_ delivery: ScheduledDelivery, showAccept: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: delivery.categoryIcon).foregroundStyle(.tint)
                Text(delivery.categoryTitle).font(.headline)
                Spacer()
                let driverCents = Int(Double(delivery.totalCents) * 0.70)
                Text("Earn \(PricingService.Quote.format(driverCents))")
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)
            }

            Label(delivery.pickupAddress, systemImage: "circle.fill")
                .font(.subheadline)
            Label(delivery.dropoffAddress, systemImage: "mappin.circle.fill")
                .font(.subheadline)

            HStack {
                Label(delivery.scheduledAt.formatted(date: .abbreviated, time: .shortened),
                      systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if showAccept {
                    Button {
                        schedule.accept(delivery.id, driverName: "You")
                    } label: {
                        Text("Accept")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                } else {
                    Label("Accepted", systemImage: "checkmark.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
