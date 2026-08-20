import Foundation
import SwiftData

/// Deleting a deck also drops what is filed under its *name*: the mirror `.txt`
/// and every difficulty stat. Import doesn't enforce unique names the way rename
/// does, so a second deck can answer to the same name — and then those artefacts
/// are its history too, and have to stay.
enum DeckDeletion {
    static func delete(_ doomed: [Deck], in context: ModelContext) {
        let doomedIDs = Set(doomed.map(\.id))
        let all = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        let survivingNames = Set(all.lazy.filter { !doomedIDs.contains($0.id) }.map(\.name))
        for deck in doomed {
            if !survivingNames.contains(deck.name) {
                DeckFileStore.remove(deck)
                DifficultyStore.shared.removeDeck(named: deck.name)
            }
            context.delete(deck)
        }
    }
}
