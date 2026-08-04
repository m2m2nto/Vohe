import XCTest
import SwiftData
@testable import Vohe

/// What "Delete Deck" performs: the mirror file goes, and the deck takes its
/// cards, results and paused session with it. Other decks are untouched.
@MainActor
final class DeckDeletionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        let schema = Schema([Deck.self, Card.self, SessionResult.self, PausedSession.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    private func makeDeck(name: String) -> Deck {
        let deck = Deck(name: name, language1: "Croatian", language2: "Italian")
        context.insert(deck)
        let card = Card(front: "pas", back: "cane")
        card.deck = deck
        context.insert(card)
        let result = SessionResult(total: 1, correct: 1, inverted: false, startedAt: .now, wrongCardIDs: [])
        result.deck = deck
        context.insert(result)
        let paused = PausedSession(
            cardOrderIDs: [card.id], currentIndex: 0, correct: 0,
            inverted: false, wordCount: 5, startedAt: .now,
            wrongCardIDs: [], gradedCardIDs: [], againCounts: [:]
        )
        paused.deck = deck
        context.insert(paused)
        return deck
    }

    private func count<T: PersistentModel>(_ type: T.Type) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }

    func testDeletingADeckRemovesItsCardsResultsAndPausedSession() throws {
        let deck = makeDeck(name: "Croatian-Italian")
        let survivor = makeDeck(name: "Spanish-Italian")
        try context.save()

        context.delete(deck)
        try context.save()

        XCTAssertEqual(try count(Deck.self), 1)
        XCTAssertEqual(try count(Card.self), 1)
        XCTAssertEqual(try count(SessionResult.self), 1)
        XCTAssertEqual(try count(PausedSession.self), 1)
        XCTAssertEqual(survivor.cards.count, 1, "the other deck keeps everything it had")
    }

    func testRemoveDeletesOnlyThatDecksMirrorFile() throws {
        let deck = makeDeck(name: "Croatian-Italian")
        let survivor = makeDeck(name: "Spanish-Italian")
        try DeckFileStore.write(deck)
        try DeckFileStore.write(survivor)
        defer { DeckFileStore.remove(survivor) }

        DeckFileStore.remove(deck)

        XCTAssertFalse(FileManager.default.fileExists(atPath: DeckFileStore.url(for: deck).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: DeckFileStore.url(for: survivor).path))
    }
}
