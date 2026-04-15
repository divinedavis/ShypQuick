import Foundation
import CoreLocation

/// Pricing rules for ShypQuick deliveries.
///
/// - Small items: $40 base
/// - Medium items: $75 base (in-between tier)
/// - Large items (couches, appliances, furniture): $150 base
/// - Long distance (> 15 miles / ~24 km between pickup and dropoff): minimum $150
/// - Same-hour rush (customer wants it picked up within the current hour): +$30
enum PricingService {
    static let longDistanceThresholdMeters: Double = 24_140 // 15 miles
    static let sameHourSurchargeCents = 3_000
    static let longDistanceMinimumCents = 15_000

    struct Quote: Equatable {
        let baseCents: Int
        let longDistanceBumpCents: Int
        let sameHourSurchargeCents: Int
        let totalCents: Int
        let distanceMeters: Double
        let isLongDistance: Bool

        var dollars: String { Self.format(totalCents) }

        static func format(_ cents: Int) -> String {
            let dollars = Double(cents) / 100.0
            return String(format: "$%.2f", dollars)
        }
    }

    static func baseCents(for size: ItemSize) -> Int {
        switch size {
        case .small:  return 4_000   // $40
        case .medium: return 7_500   // $75
        case .large:  return 15_000  // $150
        }
    }

    static func quote(
        size: ItemSize,
        pickup: CLLocationCoordinate2D,
        dropoff: CLLocationCoordinate2D,
        sameHour: Bool
    ) -> Quote {
        let distance = CLLocation(latitude: pickup.latitude, longitude: pickup.longitude)
            .distance(from: CLLocation(latitude: dropoff.latitude, longitude: dropoff.longitude))

        let base = baseCents(for: size)
        let isLongDistance = distance > longDistanceThresholdMeters

        var total = base
        var longDistanceBump = 0
        if isLongDistance && total < longDistanceMinimumCents {
            longDistanceBump = longDistanceMinimumCents - total
            total = longDistanceMinimumCents
        }

        let rush = sameHour ? sameHourSurchargeCents : 0
        total += rush

        return Quote(
            baseCents: base,
            longDistanceBumpCents: longDistanceBump,
            sameHourSurchargeCents: rush,
            totalCents: total,
            distanceMeters: distance,
            isLongDistance: isLongDistance
        )
    }
}
