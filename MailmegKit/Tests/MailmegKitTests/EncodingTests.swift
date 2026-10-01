import XCTest
@testable import MailmegKit

final class EncodingTests: XCTestCase {
    func testBase64URLRoundTrip() {
        let data = Data([0xFB, 0xFF, 0xFE, 0x00, 0x41])
        let encoded = Base64URL.encode(data)
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("="))
        XCTAssertEqual(Base64URL.decode(encoded), data)
    }

    func testBase64URLDecodesPaddedInput() {
        XCTAssertEqual(Base64URL.decode("SGk="), Data("Hi".utf8))
        XCTAssertEqual(Base64URL.decode("SGk"), Data("Hi".utf8))
    }

    func testPKCEMatchesRFC7636Example() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        XCTAssertEqual(pkce.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testRandomPKCEVerifierLength() {
        let pkce = PKCE()
        XCTAssertGreaterThanOrEqual(pkce.verifier.count, 43)
        XCTAssertNotEqual(pkce.verifier, PKCE().verifier)
    }

    func testFormEncodingEscapesNonASCII() {
        let body = String(decoding: FormEncoding.encode([("a b", "ü&=/")]), as: UTF8.self)
        XCTAssertEqual(body, "a%20b=%C3%BC%26%3D%2F")
    }

    func testHeaderValueParsing() {
        let value = HeaderValue("text/plain; charset=\"ISO-8859-1\"; format=flowed")
        XCTAssertEqual(value.value, "text/plain")
        XCTAssertEqual(value["charset"], "ISO-8859-1")
        XCTAssertEqual(value["FORMAT"], "flowed")
    }

    func testTextDecodingHonoursCharset() {
        let latin1 = Data([0x47, 0x72, 0xFC, 0xDF, 0x65])
        XCTAssertEqual(TextDecoding.string(from: latin1, charset: "iso-8859-1"), "Grüße")
        XCTAssertEqual(TextDecoding.string(from: Data("Grüße".utf8), charset: nil), "Grüße")
    }

    func testHTMLEntityDecoding() {
        XCTAssertEqual(HTMLText.decodeEntities("It&#39;s &lt;b&gt; &amp;amp; &#x1F600;"), "It's <b> &amp; 😀")
    }

    func testHTMLToPlainText() {
        let html = "<html><head><style>p{}</style></head><body><p>Hello&nbsp;<b>World</b></p><div>Line<br>two</div></body></html>"
        XCTAssertEqual(HTMLText.plainText(fromHTML: html), "Hello World\nLine\ntwo")
    }

    func testPlainTextToHTMLLinkifies() {
        let html = HTMLText.html(fromPlainText: "See https://example.com <now>")
        XCTAssertEqual(html, "See <a href=\"https://example.com\">https://example.com</a> &lt;now&gt;")
    }
}
