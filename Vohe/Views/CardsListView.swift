import SwiftUI
import SwiftData

struct CardsListView: View {
    @Bindable var deck: Deck
    @Environment(\.modelContext) private var context

    @State private var editingCard: Card?
    @State private var addingCard = false
    @State private var fileError: String?

    private var sortedCards: [Card] {
        deck.cards.sorted { $0.front.localizedCaseInsensitiveCompare($1.front) == .orderedAscending }
    }

    var body: some View {
        List {
            if deck.cards.isEmpty {
                ContentUnavailableView(
                    "No Cards",
                    systemImage: "rectangle.on.rectangle.slash",
                    description: Text("Tap + to add your first card.")
                )
            } else {
                ForEach(sortedCards) { card in
                    Button {
                        editingCard = card
                    } label: {
                        CardRow(card: card, inLinkedDeck: deck.isLinked)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("Cards (\(deck.cards.count))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { addingCard = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add card")
            }
        }
        .sheet(isPresented: $addingCard) {
            CardEditorSheet(deck: deck, mode: .add) { front, back, needsValidation in
                addCard(front: front, back: back, needsValidation: needsValidation)
            }
        }
        .sheet(item: $editingCard) { card in
            CardEditorSheet(deck: deck, mode: .edit(card)) { front, back, _ in
                update(card: card, front: front, back: back)
            }
        }
        .alert(
            "Couldn't Update File",
            isPresented: Binding(
                get: { fileError != nil },
                set: { if !$0 { fileError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { fileError = nil }
        } message: {
            Text(fileError ?? "")
        }
    }

    private func addCard(front: String, back: String, needsValidation: Bool) {
        let card = Card(front: front, back: back)
        card.needsValidation = needsValidation
        card.deck = deck
        context.insert(card)
        try? context.save()
        syncFile()
    }

    private func update(card: Card, front: String, back: String) {
        let wasUnvalidated = card.needsValidation
        card.needsValidation = false
        let oldFront = card.front
        let oldBack = card.back
        guard oldFront != front || oldBack != back else {
            if wasUnvalidated { try? context.save() }
            return
        }
        card.front = front
        card.back = back
        try? context.save()
        DifficultyStore.shared.rename(
            deckName: deck.name,
            oldFront: oldFront, oldBack: oldBack,
            newFront: front, newBack: back
        )
        syncFile()
    }

    private func delete(at offsets: IndexSet) {
        let cards = sortedCards
        for idx in offsets {
            let card = cards[idx]
            DifficultyStore.shared.remove(deckName: deck.name, front: card.front, back: card.back)
            context.delete(card)
        }
        try? context.save()
        syncFile()
    }

    private func syncFile() {
        do {
            try DeckFileStore.write(deck)
        } catch {
            fileError = error.localizedDescription
        }
    }
}

private struct CardRow: View {
    let card: Card
    /// Marks are only meaningful when the deck is linked to a dictionary.
    let inLinkedDeck: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.front)
                .font(.body.weight(.semibold))
            HStack(spacing: 6) {
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(card.back)
                    .foregroundStyle(.secondary)
                if card.needsValidation {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Suggested translation, not yet validated")
                }
                if inLinkedDeck && card.pendingReview {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .accessibilityLabel("Waiting for review on the dictionary server")
                } else if inLinkedDeck && card.needsSubmission {
                    Image(systemName: "iphone")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Only on this iPhone")
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
