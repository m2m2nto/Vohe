import Foundation
import SwiftData

@Model
final class Deck {
    @Attribute(.unique) var id: UUID
    var name: String
    var language1: String
    var language2: String
    var createdAt: Date

    /// Set once the deck is linked to a dictionary on the backend; nil for
    /// decks that only ever came from a `.txt` file.
    var remoteID: Int? = nil
    /// Version of the remote dictionary this deck last pulled.
    var syncedVersion: Int = 0
    /// Highest version seen in the catalog. Higher than `syncedVersion` means
    /// an update is waiting; the user decides when to take it.
    var latestRemoteVersion: Int = 0

    var isLinked: Bool { remoteID != nil }
    var updateAvailable: Bool { isLinked && latestRemoteVersion > syncedVersion }

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
