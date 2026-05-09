import XCTest

/// End-to-end XCUITest of the customer pricing flow.
/// Launches the app with `-SHYP_UI_TEST 1` so it skips Supabase auth and
/// drops straight into `CustomerHomeView` with a stub Profile.
final class PricingFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-SHYP_UI_TEST", "1"]
        app.launch()
    }

    func testAddOnsCardExpandsAndShowsAllToggles() {
        let addOnsHeader = app.staticTexts["Add-ons"]
        XCTAssertTrue(addOnsHeader.waitForExistence(timeout: 10),
                      "Add-ons header should appear on the customer home screen")
        addOnsHeader.tap()

        XCTAssertTrue(
            app.switches["twoManCrewToggle"].waitForExistence(timeout: 8),
            "Two-man crew toggle should reveal after expanding Add-ons"
        )
        XCTAssertTrue(app.switches["assemblyToggle"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.switches["applianceHookupToggle"].waitForExistence(timeout: 2))
    }

    func testRushToggleIsLabelledFiftyDollars() {
        // The rush toggle is always visible. The label must reflect the new
        // PDF-aligned price; if someone bumps sameHourSurchargeCents but
        // forgets to refresh the label, this test catches it.
        let rushLabel = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'within the hour' AND label CONTAINS '$50.00'")
        ).firstMatch
        XCTAssertTrue(rushLabel.waitForExistence(timeout: 10),
                      "Rush toggle should advertise +$50.00")
    }

    func testCustomerHomeScreenshotCaptured() {
        // Captures a screenshot of the customer home + add-ons-expanded
        // state and attaches it to the test report so we have a visual
        // regression artifact alongside text assertions. Apple-native via
        // XCTAttachment.
        let header = app.staticTexts["Add-ons"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        header.tap()
        // Give the disclosure animation time to settle before snapshotting.
        XCTAssertTrue(app.switches["twoManCrewToggle"].waitForExistence(timeout: 2))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "customer-home-addons-expanded"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
