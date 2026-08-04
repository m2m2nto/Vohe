import XCTest
@testable import Vohe

/// Parity with web/tests/deckFormat.test.ts — both parsers must read the same
/// .txt the same way, or a dictionary exported from the web editor imports
/// wrong here.
final class DeckParserTests: XCTestCase {
    func testSplitsOnTheFirstSpacedHyphenElseTheFirstBareOne() throws {
        let deck = try DeckParser.parse("Italian-Croatian\ncane-pas\ngatto - mačka\nne - non / no")
        XCTAssertEqual(deck.language1, "Italian")
        XCTAssertEqual(deck.language2, "Croatian")
        XCTAssertEqual(deck.pairs.map(\.front), ["cane", "gatto", "ne"])
        XCTAssertEqual(deck.pairs.map(\.back), ["pas", "mačka", "non / no"])
    }

    func testWordMayContainHyphensWhenTheLineHasASpacedSeparator() throws {
        let deck = try DeckParser.parse("Croatian-Italian\ntako-tako - cosi-cosi\nwell-being - benessere")
        XCTAssertEqual(deck.pairs.map(\.front), ["tako-tako", "well-being"])
        XCTAssertEqual(deck.pairs.map(\.back), ["cosi-cosi", "benessere"])
    }

    func testOnlyTheFirstSpacedHyphenSplits() throws {
        let deck = try DeckParser.parse("A-B\ntako-tako - cosi - cosi")
        XCTAssertEqual(deck.pairs.first?.front, "tako-tako")
        XCTAssertEqual(deck.pairs.first?.back, "cosi - cosi")
    }

    func testRejectsMalformedInput() {
        XCTAssertThrowsError(try DeckParser.parse(""))
        XCTAssertThrowsError(try DeckParser.parse("no hyphen here"))
        XCTAssertThrowsError(try DeckParser.parse("A-B"))
        XCTAssertThrowsError(try DeckParser.parse("A-B\nlonely"))
        XCTAssertThrowsError(try DeckParser.parse("A-B\n- pas"))
    }
}
