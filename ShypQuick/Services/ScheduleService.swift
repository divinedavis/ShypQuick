import Foundation
import Combine
import CoreLocation

struct ScheduledDelivery: Identifiable, Equatable {
    let id: UUID
    let pickupAddress: String
    let dropoffAddress: String
    let pickupLat: Double
    let pickupLng: Double
    let dropoffLat: Double
    let dropoffLng: Double
    let size: ItemSize
    let totalCents: Int
    let photoData: Data?
    let categoryTitle: String
    let categoryIcon: String
    let scheduledAt: Date
    let createdAt: Date
    var acceptedByDriver: String?
    var pickedUpAt: Date?
    var deliveredAt: Date?

    var isAccepted: Bool { acceptedByDriver != nil }
    var isPickedUp: Bool { pickedUpAt != nil }
    var isDelivered: Bool { deliveredAt != nil }

    /// Short status label for UI badges.
    var statusLabel: String {
        if isDelivered { return "Delivered" }
        if isPickedUp { return "Picked up" }
        if isAccepted { return "Accepted" }
        return "Waiting"
    }

    var pickupCoord: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: pickupLat, longitude: pickupLng)
    }
    var dropoffCoord: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: dropoffLat, longitude: dropoffLng)
    }
}

@MainActor
final class ScheduleService: ObservableObject {
    static let shared = ScheduleService()

    @Published var deliveries: [ScheduledDelivery] = []

    private init() {}

    func schedule(
        pickupAddress: String,
        dropoffAddress: String,
        pickup: CLLocationCoordinate2D,
        dropoff: CLLocationCoordinate2D,
        size: ItemSize,
        totalCents: Int,
        photoData: Data?,
        categoryTitle: String,
        categoryIcon: String,
        scheduledAt: Date
    ) {
        let delivery = ScheduledDelivery(
            id: UUID(),
            pickupAddress: pickupAddress,
            dropoffAddress: dropoffAddress,
            pickupLat: pickup.latitude,
            pickupLng: pickup.longitude,
            dropoffLat: dropoff.latitude,
            dropoffLng: dropoff.longitude,
            size: size,
            totalCents: totalCents,
            photoData: photoData,
            categoryTitle: categoryTitle,
            categoryIcon: categoryIcon,
            scheduledAt: scheduledAt,
            createdAt: Date(),
            acceptedByDriver: nil,
            pickedUpAt: nil,
            deliveredAt: nil
        )
        deliveries.append(delivery)
    }

    func accept(_ id: UUID, driverName: String) {
        guard let idx = deliveries.firstIndex(where: { $0.id == id }) else { return }
        deliveries[idx].acceptedByDriver = driverName
    }

    func markPickedUp(_ id: UUID) {
        guard let idx = deliveries.firstIndex(where: { $0.id == id }) else { return }
        guard deliveries[idx].isAccepted else { return }
        if deliveries[idx].pickedUpAt == nil {
            deliveries[idx].pickedUpAt = Date()
        }
    }

    func markDelivered(_ id: UUID) {
        guard let idx = deliveries.firstIndex(where: { $0.id == id }) else { return }
        guard deliveries[idx].isPickedUp else { return }
        if deliveries[idx].deliveredAt == nil {
            deliveries[idx].deliveredAt = Date()
        }
    }

    func remove(_ id: UUID) {
        deliveries.removeAll { $0.id == id }
    }
}
