import Foundation
import CoreLocation
import Combine

struct JobOffer: Identifiable, Equatable {
    let id: UUID
    let pickupAddress: String
    let dropoffAddress: String
    let pickupLat: Double
    let pickupLng: Double
    let dropoffLat: Double
    let dropoffLng: Double
    let size: ItemSize
    let sameHour: Bool
    let totalCents: Int
    let photoData: Data?
    let categoryTitle: String
    let categoryIcon: String
    let createdAt: Date

    var pickupCoord: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: pickupLat, longitude: pickupLng)
    }
    var dropoffCoord: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: dropoffLat, longitude: dropoffLng)
    }
}

@MainActor
final class DispatchService: ObservableObject {
    static let shared = DispatchService()

    /// Radius used to decide which drivers see an offer.
    static let matchRadiusMeters: Double = 16_093.4 // 10 miles

    @Published var pendingOffer: JobOffer?
    @Published var activeJob: JobOffer?

    private init() {}

    func postOffer(
        pickupAddress: String,
        dropoffAddress: String,
        pickup: CLLocationCoordinate2D,
        dropoff: CLLocationCoordinate2D,
        size: ItemSize,
        sameHour: Bool,
        totalCents: Int,
        photoData: Data?,
        categoryTitle: String,
        categoryIcon: String
    ) {
        pendingOffer = JobOffer(
            id: UUID(),
            pickupAddress: pickupAddress,
            dropoffAddress: dropoffAddress,
            pickupLat: pickup.latitude,
            pickupLng: pickup.longitude,
            dropoffLat: dropoff.latitude,
            dropoffLng: dropoff.longitude,
            size: size,
            sameHour: sameHour,
            totalCents: totalCents,
            photoData: photoData,
            categoryTitle: categoryTitle,
            categoryIcon: categoryIcon,
            createdAt: Date()
        )
    }

    func accept(_ offer: JobOffer) {
        guard pendingOffer?.id == offer.id else { return }
        activeJob = offer
        pendingOffer = nil
    }

    func decline(_ offer: JobOffer) {
        guard pendingOffer?.id == offer.id else { return }
        pendingOffer = nil
    }

    func expire(_ offer: JobOffer) {
        guard pendingOffer?.id == offer.id else { return }
        pendingOffer = nil
    }

    func clearActiveJob() {
        activeJob = nil
    }
}
