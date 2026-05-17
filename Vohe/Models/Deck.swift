import Foundation
import SwiftData

@Model
final class Deck {
    @Attribute(.unique) var id: UUID
    var name: String
    var language1: String
    var language2: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Card.deck)
    var cards: [Card] = []

    @Relationship(deleteRule: .cascade, inverse: \SessionResult.deck)
    var sessions: [SessionResult] = []

    @Relationship(deleteRule: .cascade, inverse: \PausedSession.deck)
    var pausedSessions: [PausedSession] = []

    init(name: String, language1: String, language2: String) {
        self.id = UUID()
        self.name = name
        self.language1 = language1
        self.language2 = language2
        self.createdAt = .now
    }
}
