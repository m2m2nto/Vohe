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

    /// A deck deleted while nothing else answers to its name takes its mirror
    /// file and its card stats with it.
    func testDeletingASoleDeckDropsItsFileAndStats() throws {
        let name = "DeckDeletionTests-\(UUID().uuidString)"
        let deck = makeDeck(name: name)
        try context.save()
        try DeckFileStore.write(deck)
        DifficultyStore.shared.recordAnswer(
            deckName: name, front: "pas", back: "cane", wasCorrect: false
        )

        DeckDeletion.delete([deck], in: context)
        try context.save()

        XCTAssertFalse(FileManager.default.fileExists(atPath: DeckFileStore.url(forDeckNamed: name).path))
        XCTAssertNil(DifficultyStore.shared.stats(deckName: name, front: "pas", back: "cane"))
    }

    /// Import allows two decks to share a name, and the mirror file and stats
    /// are keyed by name alone — so deleting one must leave the other's history.
    func testDeletingOneOfTwoSameNamedDecksKeepsTheSharedFileAndStats() throws {
        let name = "DeckDeletionTests-\(UUID().uuidString)"
        let deck = makeDeck(name: name)
        let twin = makeDeck(name: name)
        try context.save()
        try DeckFileStore.write(deck)
        DifficultyStore.shared.recordAnswer(
            deckName: name, front: "pas", back: "cane", wasCorrect: false
        )
        defer {
            DeckFileStore.remove(deckNamed: name)
            DifficultyStore.shared.removeDeck(named: name)
        }

        DeckDeletion.delete([deck], in: context)
        try context.save()

        XCTAssertEqual(try count(Deck.self), 1, "only the deleted deck goes")
        XCTAssertEqual(twin.cards.count, 1)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: DeckFileStore.url(forDeckNamed: name).path),
            "the surviving twin still needs the mirror file"
        )
        XCTAssertNotNil(
            DifficultyStore.shared.stats(deckName: name, front: "pas", back: "cane"),
            "the surviving twin still needs its practice history"
        )
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
