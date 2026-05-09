import XCTest
import CoreLocation
@testable import ShypQuick

/// Apple-native XCTest performance harness. The pricing math is a hot
/// path — every keystroke in the address fields recomputes it. Pin the
/// runtime so a refactor that introduces an O(n) regression here gets
/// caught.
final class PricingServicePerformanceTests: XCTestCase {
    func testQuotePerformance() {
        let pickup  = CLLocationCoordinate2D(latitude: 40.6782, longitude: -73.9442)
        let dropoff = CLLocationCoordinate2D(latitude: 40.9282, longitude: -73.9442)

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()]) {
            for _ in 0..<10_000 {
                _ = PricingService.quote(
                    size: .large,
                    pickup: pickup, dropoff: dropoff,
                    sameHour: true,
                    stairsFloors: 3,
                    twoManCrew: true
                )
            }
        }
    }
}
