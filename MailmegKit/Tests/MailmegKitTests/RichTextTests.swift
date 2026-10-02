import XCTest
@testable import MailmegKit

final class RichTextTests: XCTestCase {
    func testInlineFormatting() {
        let html = RichTextHTML.render(runs: [
            RichTextRun(text: "Hallo "),
            RichTextRun(text: "fett", isBold: true),
            RichTextRun(text: " und "),
            RichTextRun(text: "rot", isItalic: true, colorHex: "#d93025"),
            RichTextRun(text: " – "),
            RichTextRun(text: "Link", isUnderlined: true, link: "https://example.com/?a=1&b=2"),
        ])
        XCTAssertTrue(html.contains("<div>Hallo <b>fett</b> und <span style=\"color:#d93025\"><i>rot</i></span> – <u><a href=\"https://example.com/?a=1&amp;b=2\">Link</a></u></div>"), html)
    }

    func testParagraphsListsAndQuotes() {
        let text = "Liste:\n• Eins\n• Zwei\n1. Erstens\n2. Zweitens\n\n> zitiert\n> weiter"
        let html = RichTextHTML.render(runs: [RichTextRun(text: text)])
        XCTAssertTrue(html.contains("<div>Liste:</div>"))
        XCTAssertTrue(html.contains("<ul style=\"margin:0 0 0 1.4em;padding:0\"><li>Eins</li><li>Zwei</li></ul>"), html)
        XCTAssertTrue(html.contains("<ol style=\"margin:0 0 0 1.4em;padding:0\"><li>Erstens</li><li>Zweitens</li></ol>"), html)
        XCTAssertTrue(html.contains("<div><br></div>"))
        XCTAssertTrue(html.contains("<blockquote"))
        XCTAssertTrue(html.contains("zitiert<br>weiter"), html)
    }

    func testFormattingAcrossLinesAndSizes() {
        let html = RichTextHTML.render(runs: [
            RichTextRun(text: "Groß\nklein", fontSize: 22),
        ])
        XCTAssertTrue(html.contains("<div><span style=\"font-size:22px\">Groß</span></div><div><span style=\"font-size:22px\">klein</span></div>"), html)
    }

    func testSignatureIsReplacedByHTML() {
        let html = RichTextHTML.render(
            runs: [RichTextRun(text: "Hi "), RichTextRun(text: "du", isBold: true), RichTextRun(text: "\n\n-- \nAlex")],
            signatureText: "-- \nAlex",
            signatureHTML: "<b>Alex</b> Berger"
        )
        XCTAssertTrue(html.contains("<div>Hi <b>du</b></div><div><br></div><div class=\"gmail_signature\"><b>Alex</b> Berger</div>"), html)
        XCTAssertFalse(html.contains("-- "))
    }

    func testSplitKeepsFormatting() {
        let runs = [RichTextRun(text: "ab"), RichTextRun(text: "cdé", isBold: true)]
        let (before, after) = RichTextHTML.split(runs, atUTF16: 3)
        XCTAssertEqual(before, [RichTextRun(text: "ab"), RichTextRun(text: "c", isBold: true)])
        XCTAssertEqual(after, [RichTextRun(text: "dé", isBold: true)])
    }

    func testNumberedPrefix() {
        XCTAssertEqual(RichTextHTML.numberedPrefixLength("12. x"), 4)
        XCTAssertNil(RichTextHTML.numberedPrefixLength("2025 war gut"))
        XCTAssertNil(RichTextHTML.numberedPrefixLength("1.5 Liter"))
    }
}
