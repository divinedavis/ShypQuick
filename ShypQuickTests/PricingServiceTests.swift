import XCTest
import CoreLocation
@testable import ShypQuick

/// Pins the SHYP QUICK® hybrid pricing model to the values agreed in
/// the strategy doc. Add-on math is independent of the base, so these
/// tests cover each line item in isolation, then a combined scenario.
final class PricingServiceTests: XCTestCase {
    // Two coords ~5 miles apart in Brooklyn (well inside the 10-mi free radius).
    private let nearPickup  = CLLocationCoordinate2D(latitude: 40.6782, longitude: -73.9442)
    private let nearDropoff = CLLocationCoordinate2D(latitude: 40.7282, longitude: -73.9442)

    // Two coords ~17 miles apart so mileage surcharge kicks in.
    private let farPickup  = CLLocationCoordinate2D(latitude: 40.6782, longitude: -73.9442)
    private let farDropoff = CLLocationCoordinate2D(latitude: 40.9282, longitude: -73.9442)

    func testBaseFeesMatchStrategy() {
        XCTAssertEqual(PricingService.smallBaseCents, 4_500, "Small base should be $45")
        XCTAssertEqual(PricingService.largeBaseCents, 12_500, "Large base should be $125")
        XCTAssertEqual(PricingService.baseCents(for: .small), 4_500)
        XCTAssertEqual(PricingService.baseCents(for: .large), 12_500)
    }

    func testPremiumServiceFeesMatchStrategy() {
        XCTAssertEqual(PricingService.sameHourSurchargeCents, 5_000, "Rush should be $50")
        XCTAssertEqual(PricingService.stairsPerFloorCents,    2_500, "Stairs should be $25/floor")
        XCTAssertEqual(PricingService.twoManCrewCents,        7_500, "Crew should be $75")
        XCTAssertEqual(PricingService.perMileCents,             350, "Mileage should be $3.50/mi")
    }

    func testDriverShareIs70Percent() {
        XCTAssertEqual(PricingService.driverShare, 0.70, accuracy: 0.001)
    }

    func testQuoteWithinFreeRadiusHasNoMileageSurcharge() {
        let q = PricingService.quote(
            size: .small, pickup: nearPickup, dropoff: nearDropoff, sameHour: false
        )
        XCTAssertEqual(q.baseCents, 4_500)
        XCTAssertEqual(q.mileageSurchargeCents, 0, "Trips ≤ 10 mi should have no mileage surcharge")
        XCTAssertEqual(q.totalCents, 4_500)
    }

    func testQuoteBeyondFreeRadiusAddsRoundedMileage() {
        let q = PricingService.quote(
            size: .large, pickup: farPickup, dropoff: farDropoff, sameHour: false
        )
        XCTAssertGreaterThan(q.distanceMiles, 10.0)
        let expectedExtra = (q.distanceMiles - PricingService.freeMilesRadius) * Double(PricingService.perMileCents)
        XCTAssertEqual(q.mileageSurchargeCents, Int(expectedExtra.rounded()),
                       "Mileage surcharge should round to whole cents.")
        XCTAssertEqual(q.totalCents, q.baseCents + q.mileageSurchargeCents)
    }

    func testRushToggleAddsExactlyFiftyDollars() {
        let plain = PricingService.quote(size: .small, pickup: nearPickup, dropoff: nearDropoff, sameHour: false)
        let rush  = PricingService.quote(size: .small, pickup: nearPickup, dropoff: nearDropoff, sameHour: true)
        XCTAssertEqual(rush.totalCents - plain.totalCents, 5_000)
        XCTAssertEqual(rush.sameHourSurchargeCents, 5_000)
    }

    func testStairsLinearInFloorCount() {
        let zero  = PricingService.quote(size: .large, pickup: nearPickup, dropoff: nearDropoff, sameHour: false, stairsFloors: 0)
        let three = PricingService.quote(size: .large, pickup: nearPickup, dropoff: nearDropoff, sameHour: false, stairsFloors: 3)
        XCTAssertEqual(three.stairsCents, 7_500, "3 floors × $25 = $75")
        XCTAssertEqual(three.totalCents - zero.totalCents, 7_500)
    }

    func testNegativeStairsFloorsTreatedAsZero() {
        // Defensive: should never happen via the stepper, but guard the math.
        let q = PricingService.quote(size: .large, pickup: nearPickup, dropoff: nearDropoff, sameHour: false, stairsFloors: -4)
        XCTAssertEqual(q.stairsCents, 0)
    }

    func testCombinedSurchargesSumExactly() {
        let q = PricingService.quote(
            size: .large,
            pickup: nearPickup, dropoff: nearDropoff,
            sameHour: true,
            stairsFloors: 2,
            twoManCrew: true
        )
        // base 12_500 + rush 5_000 + stairs 5_000 + crew 7_500
        XCTAssertEqual(q.totalCents, 12_500 + 5_000 + 5_000 + 7_500)
    }

    func testQuoteFromSurchargesStructMatchesExplicitArgs() {
        let s = PricingService.Surcharges(
            sameHour: true, stairsFloors: 1, twoManCrew: true
        )
        let viaStruct = PricingService.quote(size: .large, pickup: nearPickup, dropoff: nearDropoff, surcharges: s)
        let viaArgs = PricingService.quote(
            size: .large, pickup: nearPickup, dropoff: nearDropoff,
            sameHour: true, stairsFloors: 1, twoManCrew: true
        )
        XCTAssertEqual(viaStruct, viaArgs)
    }

    func testDriverEarningsIsSeventyPercentOfTotal() {
        let q = PricingService.quote(size: .large, pickup: nearPickup, dropoff: nearDropoff, sameHour: true)
        XCTAssertEqual(q.driverEarningsCents, Int(Double(q.totalCents) * 0.70))
    }

    func testFormatProducesTwoDecimalDollars() {
        XCTAssertEqual(PricingService.Quote.format(0), "$0.00")
        XCTAssertEqual(PricingService.Quote.format(4_500), "$45.00")
        XCTAssertEqual(PricingService.Quote.format(12_345), "$123.45")
    }
}
