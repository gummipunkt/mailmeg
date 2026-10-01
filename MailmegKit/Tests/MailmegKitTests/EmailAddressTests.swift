import XCTest
@testable import MailmegKit

final class EmailAddressTests: XCTestCase {
    func testParsesNameAndAddress() {
        XCTAssertEqual(EmailAddress.parse("Jane Doe <jane@example.com>"), EmailAddress(name: "Jane Doe", address: "jane@example.com"))
    }

    func testParsesBareAddress() {
        XCTAssertEqual(EmailAddress.parse("  bob@example.com "), EmailAddress(address: "bob@example.com"))
    }

    func testParsesListWithQuotedCommas() {
        let list = EmailAddress.parseList("\"Doe, Jane\" <jane@example.com>, bob@example.com; Carol <carol@example.com>")
        XCTAssertEqual(list, [
            EmailAddress(name: "Doe, Jane", address: "jane@example.com"),
            EmailAddress(address: "bob@example.com"),
            EmailAddress(name: "Carol", address: "carol@example.com"),
        ])
    }

    func testIgnoresEmptyEntries() {
        XCTAssertEqual(EmailAddress.parseList("a@example.com, ,"), [EmailAddress(address: "a@example.com")])
    }

    func testFormattedQuotesSpecialCharacters() {
        XCTAssertEqual(EmailAddress(name: "Doe, Jane", address: "jane@example.com").formatted, "\"Doe, Jane\" <jane@example.com>")
        XCTAssertEqual(EmailAddress(address: "x@example.com").formatted, "x@example.com")
    }
}
