import XCTest

/// Drives the app in demo mode (no Google account needed) and records screenshots.
final class MailmegUITests: XCTestCase {
    private static let screenshotDirectory = URL(fileURLWithPath: "/tmp/mailmeg-screenshots", isDirectory: true)

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        app.activate()
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func snapshot(_ name: String, of screenshot: XCUIScreenshot) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        try? FileManager.default.createDirectory(at: Self.screenshotDirectory, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: Self.screenshotDirectory.appendingPathComponent("\(name).png"))
    }

    func testSidebarSwitchesMailboxes() {
        let app = launch(["--demo"])

        let inboxThread = element(app, "thread.t-projektplan")
        XCTAssertTrue(inboxThread.waitForExistence(timeout: 20), "Inbox should list the demo conversations")
        inboxThread.click()
        XCTAssertTrue(element(app, "detail.subject").waitForExistence(timeout: 10), "Selecting a conversation should open it")
        sleep(2)
        snapshot("1-posteingang", of: app.windows.firstMatch.screenshot())

        let sent = element(app, "sidebar.SENT")
        print("SIDEBAR-SENT element: \(sent.debugDescription)")
        sent.click()
        sleep(2)
        XCTAssertEqual(element(app, "mailbox.title").label, "Gesendet", "The mailbox header should switch to „Gesendet“")
        snapshot("1b-nach-klick-gesendet", of: app.windows.firstMatch.screenshot())
        print("MAILBOX-TITLE after click: \(element(app, "mailbox.title").label)")
        print("SIDEBAR-HIERARCHY:\n\(app.outlines.firstMatch.debugDescription)")
        XCTAssertTrue(element(app, "thread.t-wohnung").waitForExistence(timeout: 10), "Clicking „Gesendet“ must show sent mail")
        XCTAssertFalse(element(app, "thread.t-projektplan").exists, "Inbox conversations must disappear after switching")

        element(app, "sidebar.Label_3").click()
        let travelThread = element(app, "thread.t-flug")
        XCTAssertTrue(travelThread.waitForExistence(timeout: 10), "Clicking a user label must show its conversations")
        travelThread.click()
        sleep(3)
        snapshot("2-label-reisen", of: app.windows.firstMatch.screenshot())

        element(app, "sidebar.INBOX").click()
        XCTAssertTrue(element(app, "thread.t-projektplan").waitForExistence(timeout: 10), "Going back to the inbox must work")
    }

    func testDarkMode() {
        let app = launch(["--demo", "--dark"])
        let thread = element(app, "thread.t-kaffee")
        XCTAssertTrue(thread.waitForExistence(timeout: 20))
        thread.click()
        XCTAssertTrue(element(app, "detail.subject").waitForExistence(timeout: 10))
        sleep(2)
        snapshot("3-dunkel", of: app.windows.firstMatch.screenshot())
    }

    func testComposeWindow() {
        let app = launch(["--demo"])
        let compose = element(app, "compose")
        XCTAssertTrue(compose.waitForExistence(timeout: 20))
        compose.click()
        sleep(2)
        snapshot("4-neue-email", of: XCUIScreen.main.screenshot())
        // Close the compose window so it is not restored on the next launch.
        app.typeKey("w", modifierFlags: .command)
    }

    func testOnboardingAndDemo() {
        let app = launch(["--onboarding"])
        let demoButton = element(app, "onboarding.demo")
        XCTAssertTrue(demoButton.waitForExistence(timeout: 20))
        sleep(1)
        snapshot("5-willkommen", of: app.windows.firstMatch.screenshot())
        demoButton.click()
        XCTAssertTrue(element(app, "thread.t-projektplan").waitForExistence(timeout: 20), "The demo button should open the sample mailbox")
    }
}
