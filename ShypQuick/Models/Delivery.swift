import Foundation
import CoreLocation

enum DeliveryStatus: String, Codable {
    case requested
    case accepted
    case pickedUp = "picked_up"
    case delivered
    case cancelled
}

enum ItemSize: String, Codable, CaseIterable {
    case small
    case large
}

struct Delivery: Codable, Identifiable, Equatable {
    let id: UUID
    let customerId: UUID
    var driverId: UUID?

    var pickupAddress: String
    var pickupLat: Double
    var pickupLng: Double

    var dropoffAddress: String
    var dropoffLat: Double
    var dropoffLng: Double

    var itemDescription: String?
    var itemSize: ItemSize?

    var status: DeliveryStatus
    var priceCents: Int

    var requestedAt: Date?
    var acceptedAt: Date?
    var pickedUpAt: Date?
    var deliveredAt: Date?

    var pickupCoordinate: CLLocationCoordinate2D {
        .init(latitude: pickupLat, longitude: pickupLng)
    }

    var dropoffCoordinate: CLLocationCoordinate2D {
        .init(latitude: dropoffLat, longitude: dropoffLng)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case customerId = "customer_id"
        case driverId = "driver_id"
        case pickupAddress = "pickup_address"
        case pickupLat = "pickup_lat"
        case pickupLng = "pickup_lng"
        case dropoffAddress = "dropoff_address"
        case dropoffLat = "dropoff_lat"
        case dropoffLng = "dropoff_lng"
        case itemDescription = "item_description"
        case itemSize = "item_size"
        case status
        case priceCents = "price_cents"
        case requestedAt = "requested_at"
        case acceptedAt = "accepted_at"
        case pickedUpAt = "picked_up_at"
        case deliveredAt = "delivered_at"
    }
}
