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
    /// True while `back` came from the on-device model and hasn't been confirmed
    /// by the user. Unvalidated cards can't be promoted past box 1.
    var needsValidation: Bool = false
    var deck: Deck?

    init(front: String, back: String) {
        self.id = UUID()
        self.front = front
        self.back = back
        self.wrongLastSession = false
    }
}
