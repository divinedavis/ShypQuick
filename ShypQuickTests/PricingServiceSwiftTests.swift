import Testing
import CoreLocation
@testable import ShypQuick

/// Modern Swift Testing (`@Test` macro, Apple, 2024) variant of the pricing
/// suite. Coexists with the XCTest suite — both run via `xcodebuild test`.
/// Swift Testing's parameterized `arguments:` form lets us check every base
/// fee in one declaration instead of one method per case.
@Suite("Pricing — Swift Testing")
struct PricingServiceSwiftTests {
    private let nearPickup  = CLLocationCoordinate2D(latitude: 40.6782, longitude: -73.9442)
    private let nearDropoff = CLLocationCoordinate2D(latitude: 40.7282, longitude: -73.9442)

    @Test("Each ItemSize maps to the strategy doc base fee",
          arguments: [
            (ItemSize.small, 4_500),
            (ItemSize.large, 12_500)
          ])
    func baseFeeMatchesSize(size: ItemSize, expected: Int) {
        #expect(PricingService.baseCents(for: size) == expected)
    }

    @Test("Stairs surcharge is linear in floor count",
          arguments: [0, 1, 3, 7])
    func stairsScalesLinearlyWithFloors(floors: Int) {
        let q = PricingService.quote(
            size: .large,
            pickup: nearPickup, dropoff: nearDropoff,
            sameHour: false, stairsFloors: floors
        )
        #expect(q.stairsCents == floors * PricingService.stairsPerFloorCents)
    }

    @Test("Premium service fees match the strategy doc")
    func premiumFeesMatchDoc() {
        #expect(PricingService.sameHourSurchargeCents == 5_000)
        #expect(PricingService.stairsPerFloorCents    == 2_500)
        #expect(PricingService.twoManCrewCents        == 7_500)
        #expect(PricingService.assemblyCents          == 5_000)
        #expect(PricingService.applianceHookupCents   == 4_000)
    }

    @Test("Driver share is the top of the strategy doc range")
    func driverShareIs70Percent() {
        #expect(PricingService.driverShare == 0.70)
    }

    @Test("Surcharges struct produces the same quote as explicit args")
    func surchargesStructMatchesExplicitArgs() {
        let s = PricingService.Surcharges(
            sameHour: true, stairsFloors: 2, twoManCrew: true,
            assembly: false, applianceHookup: true
        )
        let viaStruct = PricingService.quote(
            size: .large, pickup: nearPickup, dropoff: nearDropoff, surcharges: s
        )
        let viaArgs = PricingService.quote(
            size: .large, pickup: nearPickup, dropoff: nearDropoff,
            sameHour: true, stairsFloors: 2, twoManCrew: true,
            assembly: false, applianceHookup: true
        )
        #expect(viaStruct == viaArgs)
    }
}
