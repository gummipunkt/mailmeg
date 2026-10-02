import XCTest

/// Drives the app in demo mode (no Google account needed) and records screenshots.
final class MailmegUITests: XCTestCase {
    private static let screenshotDirectory = URL(fileURLWithPath: "/tmp/mailmeg-screenshots", isDirectory: true)

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String], language: String = "de") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + ["--lang=\(language)"]
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
        let important = inboxThread.descendants(matching: .any).matching(NSPredicate(format: "label == 'Wichtig' OR value == 'Wichtig'")).firstMatch
        XCTAssertTrue(important.exists, "Important conversations should be marked in the list")
        inboxThread.click()
        XCTAssertTrue(element(app, "detail.subject").waitForExistence(timeout: 10), "Selecting a conversation should open it")
        sleep(2)
        snapshot("1-posteingang", of: app.windows.firstMatch.screenshot())

        let sent = element(app, "sidebar.SENT")
        print("SIDEBAR-SENT element: \(sent.debugDescription)")
        sent.click()
        sleep(2)
        XCTAssertEqual(element(app, "mailbox.title").value as? String, "Gesendet", "The mailbox header should switch to „Gesendet“")
        snapshot("1b-nach-klick-gesendet", of: app.windows.firstMatch.screenshot())
        print("MAILBOX-TITLE after click: \(String(describing: element(app, "mailbox.title").value))")
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
        // Wait until the account (incl. its Gmail aliases and signatures) has loaded.
        XCTAssertTrue(element(app, "thread.t-projektplan").waitForExistence(timeout: 20))
        sleep(1)
        compose.click()
        XCTAssertTrue(element(app, "compose.from").waitForExistence(timeout: 10), "The sender picker should list the Gmail aliases")
        let body = element(app, "compose.body")
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertTrue((body.value as? String ?? "").contains("Alex Berger"), "The Gmail signature should be inserted")
        sleep(1)
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

    func testEnglishInterface() {
        let app = launch(["--demo"], language: "en")
        let thread = element(app, "thread.t-projektplan")
        XCTAssertTrue(thread.waitForExistence(timeout: 20))
        XCTAssertEqual(element(app, "mailbox.title").value as? String, "Inbox")
        thread.click()
        XCTAssertTrue(element(app, "detail.subject").waitForExistence(timeout: 10))
        sleep(2)
        snapshot("6-english", of: app.windows.firstMatch.screenshot())

        element(app, "sidebar.SENT").click()
        XCTAssertTrue(element(app, "thread.t-wohnung").waitForExistence(timeout: 10))
        XCTAssertEqual(element(app, "mailbox.title").value as? String, "Sent")
    }

    func testDraftsAutosaveAndEdit() {
        let app = launch(["--demo"])
        XCTAssertTrue(element(app, "thread.t-projektplan").waitForExistence(timeout: 20))
        sleep(1)

        // A new message is saved as a Gmail draft automatically.
        element(app, "compose").click()
        let subject = element(app, "compose.subject")
        XCTAssertTrue(subject.waitForExistence(timeout: 10))
        subject.click()
        subject.typeText("Testentwurf")
        let status = element(app, "compose.status")
        let saved = NSPredicate(format: "label CONTAINS[c] 'gesichert'")
        expectation(for: saved, evaluatedWith: status)
        waitForExpectations(timeout: 15)
        snapshot("7-entwurf-gesichert", of: XCUIScreen.main.screenshot())
        app.typeKey("w", modifierFlags: .command)

        // It shows up in Drafts and opens again on double-click.
        element(app, "sidebar.DRAFT").click()
        let savedDraft = element(app, "thread.t-draft-1")
        XCTAssertTrue(savedDraft.waitForExistence(timeout: 10), "The saved draft should be listed in Drafts")
        savedDraft.doubleClick()
        let body = element(app, "compose.body")
        XCTAssertTrue(body.waitForExistence(timeout: 10), "Double-clicking a draft should open it for editing")
        XCTAssertEqual(element(app, "compose.subject").value as? String, "Testentwurf")
        app.typeKey("w", modifierFlags: .command)

        // Drafts can also be edited from the conversation view.
        let existing = element(app, "thread.t-entwurf")
        XCTAssertTrue(existing.waitForExistence(timeout: 10))
        existing.click()
        let edit = element(app, "draft.edit")
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.click()
        XCTAssertTrue(element(app, "compose.body").waitForExistence(timeout: 10))
        XCTAssertTrue((element(app, "compose.body").value as? String ?? "").contains("Angebot"))
    }

    func testSourceHeadersAndRecipientDetails() {
        let app = launch(["--demo"])
        let thread = element(app, "thread.t-projektplan")
        XCTAssertTrue(thread.waitForExistence(timeout: 20))
        thread.click()
        XCTAssertTrue(element(app, "detail.subject").waitForExistence(timeout: 10))
        sleep(1)

        // The exact address the message went to is listed in the details.
        let details = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'message.details.'")).firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.click()
        XCTAssertTrue(element(app, "message.detailsGrid").waitForExistence(timeout: 5), "Clicking the recipients should show the details")
        let ownAddress = NSPredicate(format: "value CONTAINS 'alex@example.com' OR label CONTAINS 'alex@example.com'")
        XCTAssertTrue(app.staticTexts.matching(ownAddress).firstMatch.exists, "The own address should be shown, not just „mich“")
        sleep(1)
        snapshot("8-details-empfaenger", of: app.windows.firstMatch.screenshot())

        // Message source (⌥⌘U), then switch to the header list.
        app.typeKey("u", modifierFlags: [.command, .option])
        let source = app.textViews["source.text"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 10), "⌥⌘U should open the message source")
        XCTAssertTrue((source.value as? String ?? "").contains("Delivered-To: alex@example.com"))
        sleep(1)
        snapshot("9-quelltext", of: XCUIScreen.main.screenshot())
        app.typeKey("w", modifierFlags: .command)

        app.typeKey("h", modifierFlags: [.command, .shift])
        XCTAssertTrue(element(app, "source.headers").waitForExistence(timeout: 10), "⇧⌘H should list the headers")
        sleep(1)
        snapshot("10-header", of: XCUIScreen.main.screenshot())
        app.typeKey("w", modifierFlags: .command)

        // Next / previous conversation.
        let next = element(app, "detail.next")
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.click()
        sleep(1)
        XCTAssertNotEqual(element(app, "detail.subject").value as? String, "Projektplan Q4")
    }

    func testRichTextFormatting() {
        let app = launch(["--demo"])
        XCTAssertTrue(element(app, "thread.t-projektplan").waitForExistence(timeout: 20))
        sleep(1)
        element(app, "compose").click()
        let body = element(app, "compose.body")
        XCTAssertTrue(body.waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "format.bold").exists, "The format bar should be shown")
        body.click()
        app.typeKey(.upArrow, modifierFlags: .command)
        app.typeKey("b", modifierFlags: .command)
        body.typeText("Fett ")
        app.typeKey("b", modifierFlags: .command)
        app.typeKey("i", modifierFlags: .command)
        body.typeText("kursiv")
        app.typeKey("i", modifierFlags: .command)
        body.typeText("\n")
        element(app, "format.bullets").click()
        body.typeText("Punkt eins\nPunkt zwei\n")
        XCTAssertTrue((body.value as? String ?? "").contains("• Punkt eins\n• Punkt zwei"), "Lists should continue on Return")
        sleep(1)
        snapshot("11-rich-text", of: XCUIScreen.main.screenshot())
        app.typeKey("w", modifierFlags: .command)
    }
}
