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

    /// The key format outlives any single build: change it and every stat
    /// already in `difficulty.json` is orphaned rather than read.
    func testKeyFormatIsStable() {
        XCTAssertEqual(
            DifficultyStore.key(deckName: "Deck", front: "f", back: "b"),
            "Deck\u{1F}f\u{1F}b"
        )
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

    /// Timings are averaged over the samples that carried them, and a grade
    /// recorded without timings leaves the averages alone.
    func testTimingsAverageOverSampledAnswers() {
        cards.append(("timed", "t"))
        DifficultyStore.shared.recordAnswer(
            deckName: deckName, front: "timed", back: "t", wasCorrect: true,
            timing: (flip: 2, swipe: 1)
        )
        DifficultyStore.shared.recordAnswer(
            deckName: deckName, front: "timed", back: "t", wasCorrect: true,
            timing: (flip: 4, swipe: 3)
        )
        DifficultyStore.shared.recordAnswer(
            deckName: deckName, front: "timed", back: "t", wasCorrect: false
        )

        let stats = DifficultyStore.shared.stats(deckName: deckName, front: "timed", back: "t")
        XCTAssertEqual(stats?.seen, 3)
        XCTAssertEqual(stats?.timed, 2)
        XCTAssertEqual(stats?.flipSeconds ?? 0, 6, accuracy: 0.001)
        XCTAssertEqual(stats?.swipeSeconds ?? 0, 4, accuracy: 0.001)

        let timing = DifficultyStore.shared.timedCards().first { $0.deckName == deckName }
        XCTAssertEqual(timing?.front, "timed")
        XCTAssertEqual(timing?.times, 2)
        XCTAssertEqual(timing?.averageFlipSeconds ?? 0, 3, accuracy: 0.001)
        XCTAssertEqual(timing?.averageSwipeSeconds ?? 0, 2, accuracy: 0.001)
    }

    /// Deleting a deck takes its stats with it, and leaves every other deck's
    /// alone — the prefix match must not reach a deck that merely starts the same.
    func testDeletingADeckRemovesOnlyItsOwnStats() {
        record(front: "gone", back: "g", seen: 3, wrong: 1)
        let neighbour = deckName + " Advanced"
        DifficultyStore.shared.recordAnswer(
            deckName: neighbour, front: "kept", back: "k", wasCorrect: true
        )
        defer { DifficultyStore.shared.remove(deckName: neighbour, front: "kept", back: "k") }

        DifficultyStore.shared.removeDeck(named: deckName)

        XCTAssertNil(DifficultyStore.shared.stats(deckName: deckName, front: "gone", back: "g"))
        XCTAssertNotNil(DifficultyStore.shared.stats(deckName: neighbour, front: "kept", back: "k"))
    }

    /// A card graded but never timed stays out of the metrics list.
    func testUntimedCardsAreNotListed() {
        record(front: "untimed", back: "u", seen: 3, wrong: 1)

        XCTAssertTrue(DifficultyStore.shared.timedCards().allSatisfy { $0.deckName != deckName })
    }

    /// `difficulty.json` written before timings existed must still decode.
    func testLegacyStatsDecodeWithoutTimings() throws {
        let data = Data(#"{"seen":4,"wrong":1}"#.utf8)

        let stats = try JSONDecoder().decode(CardStats.self, from: data)

        XCTAssertEqual(stats.seen, 4)
        XCTAssertEqual(stats.wrong, 1)
        XCTAssertEqual(stats.timed, 0)
        XCTAssertEqual(stats.flipSeconds, 0)
        XCTAssertEqual(stats.swipeSeconds, 0)
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
