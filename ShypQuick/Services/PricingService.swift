import Foundation
import CoreLocation

enum PricingService {
    static let perMileThresholdMeters: Double = 16_093.4 // 10 miles
    static let perMileCents = 50 // $0.50 per mile over 10
    static let sameHourSurchargeCents = 3_000

    struct Quote: Equatable {
        let baseCents: Int
        let mileageSurchargeCents: Int
        let sameHourSurchargeCents: Int
        let totalCents: Int
        let distanceMeters: Double
        let distanceMiles: Double

        var dollars: String { Self.format(totalCents) }

        static func format(_ cents: Int) -> String {
            let dollars = Double(cents) / 100.0
            return String(format: "$%.2f", dollars)
        }
    }

    static func baseCents(for size: ItemSize) -> Int {
        switch size {
        case .small:  return 4_000   // $40
        case .large:  return 15_000  // $150
        }
    }

    static func quote(
        size: ItemSize,
        pickup: CLLocationCoordinate2D,
        dropoff: CLLocationCoordinate2D,
        sameHour: Bool
    ) -> Quote {
        let rawDistance = CLLocation(latitude: pickup.latitude, longitude: pickup.longitude)
            .distance(from: CLLocation(latitude: dropoff.latitude, longitude: dropoff.longitude))
        // Guard against NaN (invalid coords) and negative numbers.
        let distance = (rawDistance.isFinite && rawDistance >= 0) ? rawDistance : 0
        let miles = distance / 1609.344

        let base = baseCents(for: size)
        var mileageSurcharge = 0
        if distance > perMileThresholdMeters {
            let extraMiles = miles - 10.0
            // Round (not truncate) to avoid systematic revenue loss on fractional miles.
            mileageSurcharge = Int((extraMiles * Double(perMileCents)).rounded())
        }

        let rush = sameHour ? sameHourSurchargeCents : 0
        let total = base + mileageSurcharge + rush

        return Quote(
            baseCents: base,
            mileageSurchargeCents: mileageSurcharge,
            sameHourSurchargeCents: rush,
            totalCents: total,
            distanceMeters: distance,
            distanceMiles: miles
        )
    }
}
