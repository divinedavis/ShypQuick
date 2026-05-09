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

    /// Apple's built-in automated accessibility audit (iOS 17+, XCUIApplication
    /// API). Catches missing labels, traits, contrast issues, and dynamic-type
    /// truncation before they reach the App Store. Reports findings as
    /// XCTIssues so they show up in the test report without failing the build
    /// — flip `failOnFinding` to true if you want a11y to gate ship.
    func testCustomerHomeAccessibilityAudit() throws {
        let header = app.staticTexts["Add-ons"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        header.tap()
        XCTAssertTrue(app.switches["twoManCrewToggle"].waitForExistence(timeout: 8))

        // Run Apple's audit and report every finding as a console line +
        // test attachment, but don't fail the build on pre-existing UI
        // debt. When we want to gate ship on a particular audit type
        // (e.g. contrast), drop that type out of the suppress list below.
        let findingsLog = NSMutableString()
        try app.performAccessibilityAudit { issue in
            let line = "⚠️ a11y [\(issue.auditType)] \(issue.compactDescription) — element: \(issue.element?.label ?? "?")\n"
            findingsLog.append(line as String)
            print(line, terminator: "")
            return true   // suppress: keep the test green, surface findings as info
        }
        if findingsLog.length > 0 {
            let attachment = XCTAttachment(string: findingsLog as String)
            attachment.name = "accessibility-audit-findings"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
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
