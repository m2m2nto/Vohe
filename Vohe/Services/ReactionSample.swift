import Foundation

/// Turns the two clocks a session keeps for one card showing into a timed
/// sample, or into nothing when the reading can't be read as a reaction.
enum ReactionSample {
    /// A card left on screen while the user's attention is elsewhere would land
    /// a multi-minute reading; past this, a half isn't a reaction time.
    static let maxSeconds: TimeInterval = 60

    /// The two halves of one answer: how long the card sat unrevealed, and how
    /// long the decision took once revealed. Nil when the card was never
    /// revealed, or when either half falls outside the plausible window.
    static func from(
        shownAt: Date,
        flippedAt: Date?,
        swipedAt: Date
    ) -> (flip: TimeInterval, swipe: TimeInterval)? {
        guard let flippedAt else { return nil }
        let flip = flippedAt.timeIntervalSince(shownAt)
        let swipe = swipedAt.timeIntervalSince(flippedAt)
        let plausible = 0...maxSeconds
        guard plausible.contains(flip), plausible.contains(swipe) else { return nil }
        return (flip, swipe)
    }
}
