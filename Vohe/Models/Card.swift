import Foundation
import SwiftData

@Model
final class Card {
    @Attribute(.unique) var id: UUID
    var front: String
    var back: String
    var wrongLastSession: Bool
    var boxIndex: Int = 0
    var nextDue: Date = Date.distantPast
    var deck: Deck?

    init(front: String, back: String) {
        self.id = UUID()
        self.front = front
        self.back = back
        self.wrongLastSession = false
    }
}
