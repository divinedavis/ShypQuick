import Foundation
import CoreLocation

/// Hybrid pricing model: base fee + mileage after free radius + premium service fees.
/// Mirrors the SHYP QUICK® Pricing & Driver Strategy doc.
enum PricingService {
    // MARK: - Base fees
    // PDF ranges: small $35–$50, furniture $85–$150, appliances $100–$175.
    // The app exposes two categories (Car=small, Truck=large). Truck covers
    // both furniture and appliances, priced at the mid of the combined range.
    static let smallBaseCents = 4_500   // $45
    static let largeBaseCents = 12_500  // $125

    // MARK: - Mileage
    // PDF range: $2.50–$5/mile after the included local radius.
    static let perMileCents = 350                        // $3.50/mile
    static let freeMilesRadius: Double = 10.0
    static let perMileThresholdMeters: Double = 16_093.4 // 10 miles

    // MARK: - Premium service fees
    static let sameHourSurchargeCents = 5_000   // $50  (rush, mid of $30–$75)
    static let stairsPerFloorCents    = 2_500   // $25 / floor
    static let twoManCrewCents        = 7_500   // $75  (mid of $50–$100)

    // MARK: - Driver compensation
    // PDF: 60–70% to driver. Top of range during expansion for retention.
    static let driverShare: Double = 0.70

    // MARK: - Surcharge bundle
    struct Surcharges: Equatable {
        var sameHour: Bool = false
        var stairsFloors: Int = 0
        var twoManCrew: Bool = false

        static let none = Surcharges()

        var hasAny: Bool {
            sameHour || stairsFloors > 0 || twoManCrew
        }
    }

    // MARK: - Quote
    struct Quote: Equatable {
        let baseCents: Int
        let mileageSurchargeCents: Int
        let sameHourSurchargeCents: Int
        let stairsCents: Int
        let twoManCrewCents: Int
        let totalCents: Int
        let distanceMeters: Double
        let distanceMiles: Double

        var dollars: String { Self.format(totalCents) }
        var driverEarningsCents: Int { Int(Double(totalCents) * driverShare) }

        static func format(_ cents: Int) -> String {
            let dollars = Double(cents) / 100.0
            return String(format: "$%.2f", dollars)
        }
    }

    static func baseCents(for size: ItemSize) -> Int {
        switch size {
        case .small: return smallBaseCents
        case .large: return largeBaseCents
        }
    }

    static func quote(
        size: ItemSize,
        pickup: CLLocationCoordinate2D,
        dropoff: CLLocationCoordinate2D,
        sameHour: Bool,
        stairsFloors: Int = 0,
        twoManCrew: Bool = false
    ) -> Quote {
        let rawDistance = CLLocation(latitude: pickup.latitude, longitude: pickup.longitude)
            .distance(from: CLLocation(latitude: dropoff.latitude, longitude: dropoff.longitude))
        // Guard against NaN (invalid coords) and negative numbers.
        let distance = (rawDistance.isFinite && rawDistance >= 0) ? rawDistance : 0
        let miles = distance / 1609.344

        let base = baseCents(for: size)
        var mileageSurcharge = 0
        if distance > perMileThresholdMeters {
            let extraMiles = miles - freeMilesRadius
            // Round (not truncate) to avoid systematic revenue loss on fractional miles.
            mileageSurcharge = Int((extraMiles * Double(perMileCents)).rounded())
        }

        let rush   = sameHour ? sameHourSurchargeCents : 0
        let stairs = max(0, stairsFloors) * stairsPerFloorCents
        let crew   = twoManCrew ? twoManCrewCents : 0

        let total = base + mileageSurcharge + rush + stairs + crew

        return Quote(
            baseCents: base,
            mileageSurchargeCents: mileageSurcharge,
            sameHourSurchargeCents: rush,
            stairsCents: stairs,
            twoManCrewCents: crew,
            totalCents: total,
            distanceMeters: distance,
            distanceMiles: miles
        )
    }

    static func quote(
        size: ItemSize,
        pickup: CLLocationCoordinate2D,
        dropoff: CLLocationCoordinate2D,
        surcharges: Surcharges
    ) -> Quote {
        quote(
            size: size,
            pickup: pickup,
            dropoff: dropoff,
            sameHour: surcharges.sameHour,
            stairsFloors: surcharges.stairsFloors,
            twoManCrew: surcharges.twoManCrew
        )
    }
}
