import XCTest
@testable import ShypQuick

/// Covers the customer-side delivery tracker's status → phase mapping.
/// `DeliverySimulation` used to be a hardcoded timer animation; it now
/// derives every phase from the real job_offers status, and this pins
/// that mapping so a status rename or new state can't silently break
/// the customer's tracking screen.
final class DeliveryTrackerTests: XCTestCase {

    func testActiveStatusesMapToTheRightPhase() {
        XCTAssertEqual(DeliverySimulation.phase(forStatus: "pending"), .searching)
        XCTAssertEqual(DeliverySimulation.phase(forStatus: "accepted"), .enRouteToPickup)
        XCTAssertEqual(DeliverySimulation.phase(forStatus: "picked_up"), .enRouteToDropoff)
        XCTAssertEqual(DeliverySimulation.phase(forStatus: "delivered"), .delivered)
    }

    func testTerminalStatusesMapToAFailedPhase() {
        for status in ["declined", "expired", "cancelled"] {
            let phase = DeliverySimulation.phase(forStatus: status)
            XCTAssertEqual(phase?.isFailed, true,
                           "\(status) should put the customer in a failed phase")
        }
    }

    func testUnknownStatusDoesNotChangeThePhase() {
        // nil means "leave the displayed phase alone" — a status we don't
        // recognise must never blank the tracking screen.
        XCTAssertNil(DeliverySimulation.phase(forStatus: "in_transit"))
        XCTAssertNil(DeliverySimulation.phase(forStatus: ""))
    }
}
