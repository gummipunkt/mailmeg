import XCTest
@testable import MailmegKit

final class QuotedTextTests: XCTestCase {
    func testReplyAboveQuote() {
        let text = "Klar, 15 Uhr passt.\n\nAlex\n\nAm 10.11.2026 um 09:38 schrieb Jonas Weber <jonas@example.org>:\n> Hey Alex,\n>\n> hast du Zeit?\n"
        let (body, quote) = QuotedText.split(text)
        XCTAssertEqual(body, "Klar, 15 Uhr passt.\n\nAlex")
        XCTAssertEqual(quote, "Am 10.11.2026 um 09:38 schrieb Jonas Weber <jonas@example.org>:\n> Hey Alex,\n>\n> hast du Zeit?")
    }

    func testWrappedAttributionAndNoAttribution() {
        let wrapped = "Sounds good.\n\nOn Tue, Nov 10, 2026 at 9:38 AM Jonas Weber <jonas@example.org>\nwrote:\n\n> Coffee?\n> Thursday?"
        XCTAssertEqual(QuotedText.split(wrapped).body, "Sounds good.")
        XCTAssertTrue(QuotedText.split(wrapped).quote?.hasPrefix("On Tue, Nov 10") == true)

        let bare = "Yes.\n> Coffee?"
        XCTAssertEqual(QuotedText.split(bare).body, "Yes.")
        XCTAssertEqual(QuotedText.split(bare).quote, "> Coffee?")
    }

    func testOutlookSeparator() {
        let text = "Danke!\n\n-----Ursprüngliche Nachricht-----\nVon: Anna\nGesendet: Montag\n\nHallo Alex"
        let (body, quote) = QuotedText.split(text)
        XCTAssertEqual(body, "Danke!")
        XCTAssertTrue(quote?.hasPrefix("-----Ursprüngliche Nachricht-----") == true)
    }

    func testNothingToFold() {
        // No quote at all.
        XCTAssertNil(QuotedText.split("Hallo\n\nGruß").quote)
        // Answers written between the quoted lines stay visible.
        XCTAssertNil(QuotedText.split("> Kaffee?\nJa!\n> Donnerstag?\nPasst.").quote)
        // Text below the quote (bottom posting) stays visible, too.
        XCTAssertNil(QuotedText.split("On Monday Anna wrote:\n> Hi\n\nMy answer").quote)
        // A message that is only a quote is not folded away.
        XCTAssertNil(QuotedText.split("> nur Zitat\n> mehr").quote)
        // Forwarded messages are content, not a quote.
        XCTAssertNil(QuotedText.split("FYI\n\n---------- Forwarded message ---------\nFrom: Anna\n\nHallo").quote)
    }
}
