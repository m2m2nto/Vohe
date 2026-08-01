import XCTest
@testable import Vohe

/// Exercises the shared store against a deck name unique to each run, so the
/// on-disk `difficulty.json` of the test host is never read for assertions and
/// the keys are removed again in tearDown.
final class DifficultyStoreTests: XCTestCase {
    private var deckName: String!
    private var cards: [(front: String, back: String)] = []

    override func setUp() {
        super.setUp()
        deckName = "DifficultyStoreTests-\(UUID().uuidString)"
        cards = []
    }

    override func tearDown() {
        for card in cards {
            DifficultyStore.shared.remove(deckName: deckName, front: card.front, back: card.back)
        }
        super.tearDown()
    }

    private func record(front: String, back: String, seen: Int, wrong: Int) {
        cards.append((front, back))
        for i in 0..<seen {
            DifficultyStore.shared.recordAnswer(
                deckName: deckName, front: front, back: back, wasCorrect: i >= wrong
            )
        }
    }

    /// Practice Hardest drills a card only when it is rankable AND has been missed.
    func testHardestCountOnlyCountsRankableMissedCards() {
        record(front: "tooFew", back: "a", seen: 2, wrong: 2)       // below minSeenForRanking
        record(front: "perfect", back: "b", seen: 5, wrong: 0)      // rankable, wrong-rate 0
        record(front: "missed", back: "c", seen: 3, wrong: 1)       // rankable, wrong-rate > 0
        cards.append(("unknown", "d"))                              // no stats at all

        XCTAssertEqual(
            DifficultyStore.shared.hardestCount(deckName: deckName, fronts: cards),
            1
        )
    }

    /// The gate must agree with `SessionView.buildOrder`'s `onlyHardest` filter:
    /// a zero count means the session would open with no cards.
    func testHardestCountMatchesSessionFilter() {
        record(front: "perfect", back: "b", seen: 5, wrong: 0)
        record(front: "alsoPerfect", back: "c", seen: 4, wrong: 0)

        let drillable = cards.filter { card in
            (DifficultyStore.shared.difficultyScore(
                deckName: deckName, front: card.front, back: card.back
            ) ?? 0) > 0
        }
        XCTAssertEqual(drillable.count, 0)
        XCTAssertEqual(
            DifficultyStore.shared.hardestCount(deckName: deckName, fronts: cards),
            drillable.count
        )
    }
}
