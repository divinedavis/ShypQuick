import SwiftUI
import MapKit
import CoreLocation

struct ScheduledJobsView: View {
    @StateObject private var schedule = ScheduleService.shared

    private var available: [ScheduledDelivery] {
        schedule.deliveries.filter { !$0.isAccepted }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    /// Accepted but not delivered yet — these need action from the driver.
    private var inProgress: [ScheduledDelivery] {
        schedule.deliveries.filter { $0.isAccepted && !$0.isDelivered }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    private var completed: [ScheduledDelivery] {
        schedule.deliveries.filter { $0.isDelivered }
            .sorted { ($0.deliveredAt ?? $0.scheduledAt) > ($1.deliveredAt ?? $1.scheduledAt) }
    }

    private func openInMaps(coord: CLLocationCoordinate2D, name: String) {
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let item = MKMapItem(location: location, address: nil)
        item.name = name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
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
                                    jobRow(delivery, mode: .available)
                                }
                            }
                        }
                        if !inProgress.isEmpty {
                            Section("In progress") {
                                ForEach(inProgress) { delivery in
                                    jobRow(delivery, mode: .inProgress)
                                }
                            }
                        }
                        if !completed.isEmpty {
                            Section("Completed") {
                                ForEach(completed) { delivery in
                                    jobRow(delivery, mode: .completed)
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

    private enum RowMode { case available, inProgress, completed }

    @ViewBuilder
    private func jobRow(_ delivery: ScheduledDelivery, mode: RowMode) -> some View {
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
                statusBadge(for: delivery)
            }

            actionRow(for: delivery, mode: mode)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func actionRow(for delivery: ScheduledDelivery, mode: RowMode) -> some View {
        switch mode {
        case .available:
            Button {
                schedule.accept(delivery.id, driverName: "You")
                // Hop the driver straight into Apple Maps with the pickup
                // already set as the destination — no copy/paste needed.
                openInMaps(
                    coord: delivery.pickupCoord,
                    name: "Pickup — \(delivery.pickupAddress)"
                )
            } label: {
                Label("Accept & navigate", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).tint(.green)

        case .inProgress:
            // Primary: navigate to the next waypoint in Apple Maps.
            Button {
                if delivery.isPickedUp {
                    openInMaps(coord: delivery.dropoffCoord, name: "Dropoff — \(delivery.dropoffAddress)")
                } else {
                    openInMaps(coord: delivery.pickupCoord, name: "Pickup — \(delivery.pickupAddress)")
                }
            } label: {
                Label(
                    delivery.isPickedUp ? "Navigate to dropoff" : "Navigate to pickup",
                    systemImage: "arrow.triangle.turn.up.right.diamond.fill"
                )
                .font(.caption.bold())
                .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(delivery.isPickedUp ? .red : .green)

            // Secondary: state transition.
            if !delivery.isPickedUp {
                Button {
                    schedule.markPickedUp(delivery.id)
                } label: {
                    Text("Mark picked up").font(.caption.bold())
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.bordered).tint(.orange)
            } else {
                Button {
                    schedule.markDelivered(delivery.id)
                } label: {
                    Text("Mark delivered").font(.caption.bold())
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.bordered).tint(.green)
            }

        case .completed:
            EmptyView()
        }
    }

    @ViewBuilder
    private func statusBadge(for delivery: ScheduledDelivery) -> some View {
        if delivery.isDelivered {
            Label("Delivered", systemImage: "checkmark.seal.fill")
                .font(.caption.bold())
                .foregroundStyle(.green)
        } else if delivery.isPickedUp {
            Label("Picked up", systemImage: "shippingbox.fill")
                .font(.caption.bold())
                .foregroundStyle(.blue)
        } else if delivery.isAccepted {
            Label("Accepted", systemImage: "checkmark.circle.fill")
                .font(.caption.bold())
                .foregroundStyle(.green)
        } else {
            Label("Waiting", systemImage: "clock.fill")
                .font(.caption.bold())
                .foregroundStyle(.orange)
        }
    }
}
