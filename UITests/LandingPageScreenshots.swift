import XCTest

/// Full-resolution PNGs of the demo mailbox for the website (`/tmp/mailmeg-screenshots/landing-*.png`).
final class LandingPageScreenshots: XCTestCase {
    private static let directory = URL(fileURLWithPath: "/tmp/mailmeg-screenshots", isDirectory: true)

    override func setUp() {
        continueAfterFailure = true
    }

    private func launch(_ arguments: [String], language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--lang=\(language)"] + arguments
        app.launch()
        app.activate()
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// The window that contains the given element (compose, source and settings windows).
    private func window(of app: XCUIApplication, containing identifier: String) -> XCUIElement {
        for index in 0..<app.windows.count {
            let candidate = app.windows.element(boundBy: index)
            if candidate.descendants(matching: .any)[identifier].firstMatch.exists { return candidate }
        }
        return app.windows.firstMatch
    }

    private func save(_ name: String, _ screenshot: XCUIScreenshot) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "landing-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: Self.directory.appendingPathComponent("landing-\(name).png"))
    }

    private func openProjectPlan(_ app: XCUIApplication) {
        let thread = element(app, "thread.t-projektplan")
        XCTAssertTrue(thread.waitForExistence(timeout: 20))
        thread.click()
        XCTAssertTrue(element(app, "detail.subject").waitForExistence(timeout: 10))
        sleep(2)
    }

    func testMainWindow() {
        for (language, dark) in [("de", false), ("de", true), ("en", false), ("en", true)] {
            let app = launch(dark ? ["--dark"] : [], language: language)
            openProjectPlan(app)
            save("\(language)-inbox-\(dark ? "dark" : "light")", app.windows.firstMatch.screenshot())
            app.terminate()
        }
    }

    func testComposeRichText() {
        for language in ["de", "en"] {
            let app = launch([], language: language)
            XCTAssertTrue(element(app, "thread.t-projektplan").waitForExistence(timeout: 20))
            sleep(1)
            element(app, "compose").click()
            let to = element(app, "compose.to")
            XCTAssertTrue(to.waitForExistence(timeout: 10))
            to.click()
            to.typeText("anna.becker@example.com")
            let subject = element(app, "compose.subject")
            subject.click()
            subject.typeText(language == "de" ? "Feedback zum Projektplan" : "Feedback on the project plan")
            let body = element(app, "compose.body")
            body.click()
            app.typeKey(.upArrow, modifierFlags: .command)
            body.typeText(language == "de" ? "Hallo Anna,\n\ndanke für den Plan – sieht " : "Hi Anna,\n\nthanks for the plan – looks ")
            app.typeKey("b", modifierFlags: .command)
            body.typeText(language == "de" ? "richtig gut" : "really good")
            app.typeKey("b", modifierFlags: .command)
            body.typeText(language == "de" ? " aus. Zwei Punkte für Donnerstag:\n" : ". Two points for Thursday:\n")
            element(app, "format.bullets").click()
            body.typeText(language == "de" ? "Budget für das Design-Review\nTermin für den " : "Budget for the design review\nDate for the ")
            app.typeKey("i", modifierFlags: .command)
            body.typeText("Launch")
            app.typeKey("i", modifierFlags: .command)
            body.typeText("\n\n")
            body.typeText(language == "de" ? "Bis dann!" : "See you then!")
            sleep(1)
            save("\(language)-compose", window(of: app, containing: "compose.body").screenshot())
            app.typeKey("w", modifierFlags: .command)
            app.terminate()
        }
    }

    func testHeadersAndSettings() {
        for language in ["de", "en"] {
            let app = launch([], language: language)
            openProjectPlan(app)
            app.typeKey("h", modifierFlags: [.command, .shift])
            XCTAssertTrue(element(app, "source.headers").waitForExistence(timeout: 10))
            sleep(1)
            save("\(language)-headers", window(of: app, containing: "source.headers").screenshot())
            app.typeKey("w", modifierFlags: .command)

            app.typeKey(",", modifierFlags: .command)
            XCTAssertTrue(element(app, "settings.refreshInterval").waitForExistence(timeout: 10))
            sleep(1)
            save("\(language)-settings", window(of: app, containing: "settings.refreshInterval").screenshot())
            app.typeKey("w", modifierFlags: .command)
            app.terminate()
        }
    }
}
