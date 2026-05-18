import XCTest

/// XCUITest of the driver's active-job flow — accept is implied, then
/// pickup → delivery. Launches as a driver with a seeded active job
/// (`-SHYP_UI_TEST_DRIVER` / `-SHYP_UI_TEST_ACTIVE_JOB`) so
/// DriverActiveJobView is on screen without needing a live accepted
/// offer or a backend round-trip.
final class DriverFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-SHYP_UI_TEST", "1",
            "-SHYP_UI_TEST_DRIVER", "1",
            "-SHYP_UI_TEST_ACTIVE_JOB", "1",
        ]
        app.launch()
    }

    func testActiveJobShowsPickupControls() {
        let markPickedUp = app.buttons["Mark picked up"]
        XCTAssertTrue(markPickedUp.waitForExistence(timeout: 12),
                      "Driver should land on the active job with a pickup control")
        XCTAssertTrue(app.buttons["Navigate to pickup"].exists,
                      "Navigate-to-pickup should be available before pickup")
    }

    func testMarkPickedUpAdvancesToDelivery() {
        let markPickedUp = app.buttons["Mark picked up"]
        XCTAssertTrue(markPickedUp.waitForExistence(timeout: 12))
        let markDelivered = app.buttons["Mark delivered"]

        // Retry the tap: on a busy simulator the first tap occasionally
        // fails to register. This is self-guarding — once the job is picked
        // up the "Mark picked up" button is replaced by "Mark delivered",
        // so the retry can't double-fire.
        for _ in 0..<3 {
            if markDelivered.exists { break }
            if markPickedUp.exists {
                _ = markPickedUp.waitForHittable(timeout: 5)
                markPickedUp.tap()
            }
            if markDelivered.waitForExistence(timeout: 6) { break }
        }

        // Once picked up, the screen flips to the drop-off leg — this is the
        // transition that used to be faked on the customer side and wrote
        // nothing to the DB.
        XCTAssertTrue(markDelivered.exists,
                      "Marking picked up should reveal the delivery control")
        XCTAssertTrue(app.buttons["Navigate to dropoff"].exists,
                      "Navigation should re-point at the drop-off after pickup")
    }
}
