import XCTest
@testable import Vohe

/// The rule that decides whether a card showing becomes a timed sample. The
/// averages in Reaction Times are only as honest as this gate.
final class ReactionSampleTests: XCTestCase {
    private let shown = Date(timeIntervalSinceReferenceDate: 1_000)

    private func sample(flipAfter: TimeInterval?, swipeAfter: TimeInterval) -> (flip: TimeInterval, swipe: TimeInterval)? {
        let flipped = flipAfter.map { shown.addingTimeInterval($0) }
        return ReactionSample.from(
            shownAt: shown,
            flippedAt: flipped,
            swipedAt: (flipped ?? shown).addingTimeInterval(swipeAfter)
        )
    }

    func testARevealedCardYieldsBothHalves() {
        let timing = sample(flipAfter: 3, swipeAfter: 2)

        XCTAssertEqual(timing?.flip ?? 0, 3, accuracy: 0.001)
        XCTAssertEqual(timing?.swipe ?? 0, 2, accuracy: 0.001)
    }

    /// Swiping without ever tapping leaves nothing to measure the decision from.
    func testACardNeverRevealedIsNotSampled() {
        XCTAssertNil(sample(flipAfter: nil, swipeAfter: 2))
    }

    func testAFlipLongerThanTheCapDropsTheWholeSample() {
        XCTAssertNil(sample(flipAfter: ReactionSample.maxSeconds + 0.01, swipeAfter: 2))
    }

    func testASwipeLongerThanTheCapDropsTheWholeSample() {
        XCTAssertNil(sample(flipAfter: 3, swipeAfter: ReactionSample.maxSeconds + 0.01))
    }

    /// The cap is the last value still worth recording, not the first one dropped.
    func testAHalfExactlyAtTheCapIsStillSampled() {
        let timing = sample(flipAfter: ReactionSample.maxSeconds, swipeAfter: ReactionSample.maxSeconds)

        XCTAssertEqual(timing?.flip ?? 0, ReactionSample.maxSeconds, accuracy: 0.001)
        XCTAssertEqual(timing?.swipe ?? 0, ReactionSample.maxSeconds, accuracy: 0.001)
    }

    /// A backwards clock (an NTP correction mid-card) must not book a negative
    /// reaction time, which would drag a card's average below zero.
    func testABackwardsClockIsNotSampled() {
        XCTAssertNil(sample(flipAfter: -1, swipeAfter: 2))
        XCTAssertNil(sample(flipAfter: 3, swipeAfter: -1))
    }
}
