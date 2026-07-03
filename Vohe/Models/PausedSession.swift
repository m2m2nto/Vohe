import Foundation
import SwiftData

@Model
final class PausedSession {
    static let cap = 5

    @Attribute(.unique) var id: UUID
    var cardOrderIDs: [UUID]
    var currentIndex: Int
    var correct: Int
    var inverted: Bool
    var wordCount: Int
    var pausedAt: Date
    var startedAt: Date = Date.distantPast
    var wrongCardIDs: [UUID] = []
    var gradedCardIDs: [UUID] = []
    var againCountCardIDs: [UUID] = []
    var againCountValues: [Int] = []
    var deck: Deck?

    /// Resuming continues the same session: the once-per-card scheduling guard
    /// and reinforcement counters survive the pause (spec criterion 12).
    var againCounts: [UUID: Int] {
        get { Dictionary(uniqueKeysWithValues: zip(againCountCardIDs, againCountValues)) }
        set {
            againCountCardIDs = Array(newValue.keys)
            againCountValues = againCountCardIDs.map { newValue[$0] ?? 0 }
        }
    }

    init(
        cardOrderIDs: [UUID],
        currentIndex: Int,
        correct: Int,
        inverted: Bool,
        wordCount: Int,
        startedAt: Date,
        wrongCardIDs: [UUID],
        gradedCardIDs: [UUID],
        againCounts: [UUID: Int]
    ) {
        self.id = UUID()
        self.cardOrderIDs = cardOrderIDs
        self.currentIndex = currentIndex
        self.correct = correct
        self.inverted = inverted
        self.wordCount = wordCount
        self.pausedAt = .now
        self.startedAt = startedAt
        self.wrongCardIDs = wrongCardIDs
        self.gradedCardIDs = gradedCardIDs
        self.againCountCardIDs = Array(againCounts.keys)
        self.againCountValues = self.againCountCardIDs.map { againCounts[$0] ?? 0 }
    }
}
