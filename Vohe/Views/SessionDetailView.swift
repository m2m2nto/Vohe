import SwiftUI
import SwiftData

struct SessionDetailView: View {
    let session: SessionResult

    private var durationText: String? {
        guard session.startedAt > .distantPast else { return nil }
        let seconds = Int(session.completedAt.timeIntervalSince(session.startedAt))
        guard seconds >= 0 else { return nil }
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private var wrongCards: [Card] {
        guard let deck = session.deck else { return [] }
        let lookup = Dictionary(uniqueKeysWithValues: deck.cards.map { ($0.id, $0) })
        return session.wrongCardIDs.compactMap { lookup[$0] }
    }

    private var legacySession: Bool {
        session.startedAt == .distantPast && session.wrongCardIDs.isEmpty
    }

    var body: some View {
        Form {
            Section("Summary") {
                LabeledContent("Date") {
                    Text(session.completedAt, format: .dateTime.weekday().month().day().hour().minute())
                }
                LabeledContent("Score") {
                    Text("\(session.correct) / \(session.total)")
                        .monospacedDigit()
                }
                LabeledContent("Duration") {
                    Text(durationText ?? "—")
                        .monospacedDigit()
                        .foregroundStyle(durationText == nil ? .secondary : .primary)
                }
                if session.inverted {
                    LabeledContent("Mode") {
                        Label("Inverted", systemImage: "arrow.left.arrow.right")
                            .labelStyle(.titleAndIcon)
                    }
                }
            }

            Section("Wrong Words (\(wrongCards.count))") {
                if legacySession {
                    Text("Not recorded for this session")
                        .foregroundStyle(.secondary)
                } else if wrongCards.isEmpty {
                    Text("All correct — nice.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(wrongCards) { card in
                        WordRow(card: card, deck: session.deck)
                    }
                }
            }
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WrongCardsView: View {
    let deck: Deck

    private var cards: [Card] {
        deck.cards.filter { $0.wrongLastSession }
    }

    var body: some View {
        Form {
            Section("Wrong Last Session (\(cards.count))") {
                if cards.isEmpty {
                    Text("No cards marked wrong.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cards) { card in
                        WordRow(card: card, deck: deck)
                    }
                }
            }
        }
        .navigationTitle("Wrong Words")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WordRow: View {
    let card: Card
    let deck: Deck?

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
            }
            if let deck {
                Text("\(deck.language1) → \(deck.language2)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
