import SwiftUI

struct MyScheduledView: View {
    @StateObject private var schedule = ScheduleService.shared

    var body: some View {
        NavigationStack {
            Group {
                if schedule.deliveries.isEmpty {
                    ContentUnavailableView(
                        "No scheduled deliveries",
                        systemImage: "calendar.badge.clock",
                        description: Text("Schedule a delivery from the Send tab.")
                    )
                } else {
                    List {
                        ForEach(schedule.deliveries) { delivery in
                            scheduledRow(delivery)
                        }
                    }
                }
            }
            .navigationTitle("Scheduled")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func scheduledRow(_ delivery: ScheduledDelivery) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: delivery.categoryIcon).foregroundStyle(.tint)
                Text(delivery.categoryTitle).font(.headline)
                Spacer()
                Text(PricingService.Quote.format(delivery.totalCents))
                    .font(.subheadline.bold())
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
                if delivery.isAccepted {
                    Label("Accepted by \(delivery.acceptedByDriver ?? "driver")", systemImage: "checkmark.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                } else {
                    Label("Waiting for driver", systemImage: "clock.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
