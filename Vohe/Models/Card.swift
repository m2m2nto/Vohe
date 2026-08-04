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
    /// The approved translation last pulled from the backend. Nil means the
    /// backend has never carried this word — the card lives only on this device.
    var remoteBack: String? = nil
    /// True while this word, in this form, is waiting to be reviewed on the
    /// backend. An update leaves such a card's text alone until the review lands.
    var pendingReview: Bool = false
    var deck: Deck?

    /// Only meaningful inside a linked deck: the word is not in the dictionary.
    var isLocalOnly: Bool { remoteBack == nil }
    /// The translation no longer matches the approved one.
    var divergesFromRemote: Bool {
        guard let remoteBack else { return false }
        return remoteBack != back
    }
    /// Nothing on the backend matches this card as it stands, so it is what a
    /// "send for review" would carry.
    var needsSubmission: Bool { isLocalOnly || divergesFromRemote }

    init(front: String, back: String) {
        self.id = UUID()
        self.front = front
        self.back = back
        self.wrongLastSession = false
    }
}
