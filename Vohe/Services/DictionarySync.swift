import Foundation
import SwiftData

/// Merges a dictionary pulled from the backend into a local Deck.
///
/// Three rules shape everything here:
///
/// 1. **Nothing local is ever deleted.** A word dropped from the dictionary on
///    the backend stays on this device, marked as local-only. Deleting cards
///    remains something only the user does, in the app.
/// 2. **Practice history survives.** Box, due date and wrong-last-session are
///    never touched; when an approved translation replaces the local one, the
///    card's `DifficultyStore` stats are carried over to the new text.
/// 3. **A word waiting for review is not overwritten** until the review lands,
///    so pressing Update doesn't wipe the very edit that is being reviewed.
enum DictionarySync {
    struct MergeReport: Equatable {
        var added = 0
        var updated = 0
        var approved = 0
        var localOnly = 0
    }

    /// Migrates per-card stats when a card's translation changes.
    typealias StatsRename = (
        _ deckName: String,
        _ oldFront: String, _ oldBack: String,
        _ newFront: String, _ newBack: String
    ) -> Void

    static let liveStatsRename: StatsRename = { deckName, oldFront, oldBack, newFront, newBack in
        DifficultyStore.shared.rename(
            deckName: deckName,
            oldFront: oldFront, oldBack: oldBack,
            newFront: newFront, newBack: newBack
        )
    }

    /// Applies `remote` to `deck` and links the two. Words are matched on the
    /// card's front text, which is what the file format and the backend both
    /// treat as the identity of an entry.
    @discardableResult
    static func apply(
        _ remote: RemoteDictionary,
        to deck: Deck,
        context: ModelContext,
        renameStats: StatsRename = liveStatsRename
    ) -> MergeReport {
        var report = MergeReport()
        var byFront: [String: Card] = [:]
        for card in deck.cards.sorted(by: { $0.front < $1.front }) where byFront[card.front] == nil {
            byFront[card.front] = card
        }

        for entry in remote.entries {
            guard let card = byFront[entry.word] else {
                let card = Card(front: entry.word, back: entry.translation)
                card.remoteBack = entry.translation
                card.deck = deck
                context.insert(card)
                byFront[entry.word] = card
                report.added += 1
                continue
            }

            let previouslyApproved = card.remoteBack
            card.remoteBack = entry.translation

            if card.back == entry.translation {
                // Either it already matched, or a proposal came back approved.
                if card.pendingReview { report.approved += 1 }
                card.pendingReview = false
                card.needsValidation = false
            } else if card.pendingReview, previouslyApproved == entry.translation {
                // The dictionary hasn't moved for this word — the review is
                // still open, so the local text stands.
                continue
            } else {
                renameStats(deck.name, card.front, card.back, card.front, entry.translation)
                card.back = entry.translation
                card.needsValidation = false
                card.pendingReview = false
                report.updated += 1
            }
        }

        // A word the dictionary no longer carries is kept, but it is now only on
        // this device — and so becomes something the user may propose again.
        let published = Set(remote.entries.map(\.word))
        for card in deck.cards where !published.contains(card.front) {
            card.remoteBack = nil
        }

        deck.remoteID = remote.id
        deck.syncedVersion = remote.version
        deck.latestRemoteVersion = max(deck.latestRemoteVersion, remote.version)
        deck.language1 = remote.language1
        deck.language2 = remote.language2
        report.localOnly = deck.cards.filter(\.isLocalOnly).count

        try? context.save()
        return report
    }

    /// The cards a "send for review" would carry: words the dictionary doesn't
    /// have, and translations that no longer match the approved one. Cards
    /// already waiting are included, so re-sending re-opens a rejected proposal
    /// (the backend ignores duplicates of one still pending).
    static func cardsNeedingSubmission(in deck: Deck) -> [Card] {
        deck.cards
            .filter(\.needsSubmission)
            .sorted { $0.front < $1.front }
    }

    static func cardsAwaitingReview(in deck: Deck) -> [Card] {
        deck.cards.filter { $0.pendingReview && $0.needsSubmission }
    }

    static func markSubmitted(_ cards: [Card]) {
        for card in cards { card.pendingReview = true }
    }

    /// The deck a remote dictionary should merge into: the one already linked to
    /// it, or an unlinked deck of the same name — so a dictionary first imported
    /// from a `.txt` adopts its backend twin instead of being duplicated.
    static func existingDeck(
        for summary: RemoteDictionarySummary,
        in decks: [Deck]
    ) -> Deck? {
        if let linked = decks.first(where: { $0.remoteID == summary.id }) { return linked }
        return decks.first { $0.remoteID == nil && $0.name == summary.name }
    }

    /// Records catalog versions so decks can badge an available update without
    /// downloading anything. Unknown dictionaries are ignored.
    static func noteCatalogVersions(
        _ catalog: [RemoteDictionarySummary],
        in decks: [Deck]
    ) {
        let versions = Dictionary(
            catalog.map { ($0.id, $0.version) },
            uniquingKeysWith: { _, latest in latest }
        )
        for deck in decks {
            guard let id = deck.remoteID, let version = versions[id] else { continue }
            deck.latestRemoteVersion = max(deck.latestRemoteVersion, version)
        }
    }
}
