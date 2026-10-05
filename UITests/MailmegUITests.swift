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

    /// yyyy-MM-dd of a day relative to today, as used in the mini calendar's identifiers.
    private func dayID(_ offset: Int) -> String {
        let day = Calendar.current.date(byAdding: .day, value: offset, to: Date())!
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    func testCalendarWeekDayAndAnswer() {
        let app = launch(["--demo"])
        XCTAssertTrue(element(app, "thread.t-projektplan").waitForExistence(timeout: 20))
        XCTAssertTrue(element(app, "sidebar.today").waitForExistence(timeout: 10), "Today's events should be listed in the sidebar")

        element(app, "sidebar.__CALENDAR__").click()
        XCTAssertTrue(element(app, "calendar.title").waitForExistence(timeout: 10), "The calendar should open from the sidebar")
        // The design review is two days from now.
        let reviewDay = element(app, "calendar.day.\(dayID(2))")
        XCTAssertTrue(reviewDay.waitForExistence(timeout: 10))
        reviewDay.click()
        element(app, "calendar.mode.week").click()
        let review = element(app, "event.design-review")
        XCTAssertTrue(review.waitForExistence(timeout: 10), "The week should show the demo events")
        sleep(1)
        snapshot("12-kalender-woche", of: app.windows.firstMatch.screenshot())

        review.click()
        XCTAssertTrue(element(app, "event.detail").waitForExistence(timeout: 5), "Clicking an event should show its details")
        let accept = element(app, "invitation.accept")
        XCTAssertTrue(accept.waitForExistence(timeout: 5), "Invited events can be answered")
        accept.click()
        sleep(1)
        snapshot("13-kalender-termin", of: app.windows.firstMatch.screenshot())
        app.typeKey(.escape, modifierFlags: [])

        element(app, "calendar.mode.day").click()
        XCTAssertTrue(element(app, "event.design-review").waitForExistence(timeout: 5))
        sleep(1)
        snapshot("14-kalender-tag", of: app.windows.firstMatch.screenshot())
    }

    func testInvitationCardInEmail() {
        let app = launch(["--demo"])
        let thread = element(app, "thread.t-einladung")
        XCTAssertTrue(thread.waitForExistence(timeout: 20))
        thread.click()
        XCTAssertTrue(element(app, "invitation.card").waitForExistence(timeout: 10), "Invitations should be shown as a card")
        let accept = element(app, "invitation.accept")
        XCTAssertTrue(accept.waitForExistence(timeout: 10), "The answer buttons appear once the event is found in the calendar")
        accept.click()
        XCTAssertTrue(element(app, "invitation.status").waitForExistence(timeout: 10), "The answer should be shown on the card")
        sleep(1)
        snapshot("15-einladung", of: app.windows.firstMatch.screenshot())
    }

    func testCreateEventFromEmail() {
        let app = launch(["--demo"])
        let thread = element(app, "thread.t-projektplan")
        XCTAssertTrue(thread.waitForExistence(timeout: 20))
        thread.click()
        XCTAssertTrue(element(app, "detail.subject").waitForExistence(timeout: 10))
        sleep(1)

        app.typeKey("e", modifierFlags: [.command, .option])
        let title = element(app, "event.title")
        XCTAssertTrue(title.waitForExistence(timeout: 10), "⌥⌘E should open a new event for the email")
        XCTAssertEqual(title.value as? String, "Projektplan Q4")
        XCTAssertTrue((element(app, "event.attendees").value as? String ?? "").contains("anna.becker@example.com"), "The people of the email are invited")
        sleep(1)
        snapshot("16-termin-aus-email", of: XCUIScreen.main.screenshot())
        element(app, "event.save").click()
        let closed = NSPredicate(format: "exists == false")
        expectation(for: closed, evaluatedWith: title)
        waitForExpectations(timeout: 10)

        app.typeKey("k", modifierFlags: [.command, .option])
        XCTAssertTrue(element(app, "agenda.demo-new-1").waitForExistence(timeout: 10), "The new event should be in the calendar")
    }

    func testEditDeleteEventAndMonthView() {
        let app = launch(["--demo"])
        XCTAssertTrue(element(app, "thread.t-projektplan").waitForExistence(timeout: 20))
        element(app, "sidebar.__CALENDAR__").click()
        // Lunch with Mia is tomorrow at 12:30.
        let tomorrow = element(app, "calendar.day.\(dayID(1))")
        XCTAssertTrue(tomorrow.waitForExistence(timeout: 10))
        tomorrow.click()
        element(app, "calendar.mode.day").click()
        let lunch = element(app, "event.lunch")
        XCTAssertTrue(lunch.waitForExistence(timeout: 10))
        lunch.click()
        let edit = element(app, "event.edit")
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "Own events can be edited")
        edit.click()

        let title = element(app, "event.title")
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.value as? String, "Mittagessen mit Mia")
        title.click()
        app.typeKey("a", modifierFlags: .command)
        title.typeText("Mittagessen mit Mia und Jonas")
        sleep(1)
        snapshot("17-termin-bearbeiten", of: XCUIScreen.main.screenshot())
        element(app, "event.save").click()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: title)
        waitForExpectations(timeout: 10)

        // The change is kept: open the editor again.
        let edited = element(app, "event.lunch")
        XCTAssertTrue(edited.waitForExistence(timeout: 5))
        if !element(app, "event.edit").exists { edited.click() }
        XCTAssertTrue(element(app, "event.edit").waitForExistence(timeout: 5))
        element(app, "event.edit").click()
        XCTAssertTrue(element(app, "event.title").waitForExistence(timeout: 10))
        XCTAssertEqual(element(app, "event.title").value as? String, "Mittagessen mit Mia und Jonas")

        // Delete it.
        element(app, "event.delete").click()
        let confirm = app.buttons.matching(NSPredicate(format: "label == 'Löschen'")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        expectation(for: gone, evaluatedWith: element(app, "event.lunch"))
        waitForExpectations(timeout: 10)

        element(app, "calendar.mode.month").click()
        XCTAssertTrue(element(app, "calendar.month").waitForExistence(timeout: 5), "The month view should open")
        sleep(1)
        snapshot("18-kalender-monat", of: app.windows.firstMatch.screenshot())
        element(app, "calendar.mode.week").click()
    }

    func testSendFileViaGoogleDrive() {
        let app = launch(["--demo", "--drive-test-file"])
        XCTAssertTrue(element(app, "thread.t-projektplan").waitForExistence(timeout: 20))
        sleep(1)
        element(app, "compose").click()
        let to = element(app, "compose.to")
        XCTAssertTrue(to.waitForExistence(timeout: 10))
        to.click()
        to.typeText("anna.becker@example.com")
        let subject = element(app, "compose.subject")
        subject.click()
        subject.typeText("Unterlagen")

        element(app, "compose.drive").click()
        let file = element(app, "drive.file.Projektunterlagen.zip")
        XCTAssertTrue(file.waitForExistence(timeout: 15), "The file should be uploaded to Google Drive and shown as a link")
        XCTAssertTrue(element(app, "drive.sharing").exists, "The sharing choice should be offered")
        sleep(1)
        snapshot("19-google-drive", of: XCUIScreen.main.screenshot())

        element(app, "compose.send").click()
        let sent = NSPredicate(format: "exists == false")
        expectation(for: sent, evaluatedWith: element(app, "compose.subject"))
        waitForExpectations(timeout: 15)
    }
}
