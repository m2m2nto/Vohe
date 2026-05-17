import Foundation
import SwiftData

@Model
final class PausedSession {
    @Attribute(.unique) var id: UUID
    var cardOrderIDs: [UUID]
    var currentIndex: Int
    var correct: Int
    var inverted: Bool
    var wordCount: Int
    var pausedAt: Date
    var startedAt: Date = Date.distantPast
    var wrongCardIDs: [UUID] = []
    var deck: Deck?

    init(
        cardOrderIDs: [UUID],
        currentIndex: Int,
        correct: Int,
        inverted: Bool,
        wordCount: Int,
        startedAt: Date,
        wrongCardIDs: [UUID]
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
    }
}
