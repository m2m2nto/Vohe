import Foundation
import SwiftData

@Model
final class SessionResult {
    @Attribute(.unique) var id: UUID
    var total: Int
    var correct: Int
    var inverted: Bool
    var completedAt: Date
    var startedAt: Date = Date.distantPast
    var wrongCardIDs: [UUID] = []
    var deck: Deck?

    init(total: Int, correct: Int, inverted: Bool, startedAt: Date, wrongCardIDs: [UUID]) {
        self.id = UUID()
        self.total = total
        self.correct = correct
        self.inverted = inverted
        self.completedAt = .now
        self.startedAt = startedAt
        self.wrongCardIDs = wrongCardIDs
    }
}
