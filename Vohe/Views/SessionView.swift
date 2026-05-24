import SwiftUI
import SwiftData

struct SessionView: View {
    enum Mode {
        case perDeck(Deck)
        case global([Card])
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let mode: Mode
    let inverted: Bool
    let wordCount: Int
    let onlyHardest: Bool
    let resume: PausedSession?

    init(deck: Deck, inverted: Bool, wordCount: Int, onlyHardest: Bool, resume: PausedSession?) {
        self.mode = .perDeck(deck)
        self.inverted = inverted
        self.wordCount = wordCount
        self.onlyHardest = onlyHardest
        self.resume = resume
    }

    init(globalCards: [Card], wordCount: Int) {
        self.mode = .global(globalCards)
        self.inverted = false
        self.wordCount = wordCount
        self.onlyHardest = false
        self.resume = nil
    }

    private var deck: Deck? {
        if case .perDeck(let d) = mode { return d }
        return nil
    }

    private var isGlobal: Bool {
        if case .global = mode { return true }
        return false
    }

    @State private var order: [Card] = []
    @State private var index = 0
    @State private var correct = 0
    @State private var wrongIDs: [UUID] = []
    @State private var startedAt: Date = .now
    @State private var isFlipped = false
    @State private var dragOffset: CGSize = .zero
    @State private var showResults = false
    @State private var showExitDialog = false
    @State private var againCountThisSession: [UUID: Int] = [:]
    @State private var gradedThisSession: Set<UUID> = []
    @State private var editingCard: Card?
    @State private var fileError: String?

    private static let reinforcementCap = 2

    var body: some View {
        VStack(spacing: 24) {
            header
            Spacer(minLength: 0)
            cardArea
            Spacer(minLength: 0)
            footer
        }
        .padding(20)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear(perform: buildOrder)
        .confirmationDialog("Exit session?", isPresented: $showExitDialog, titleVisibility: .visible) {
            if !isGlobal {
                Button("Pause") { pauseAndExit() }
            }
            Button("Discard", role: .destructive) { discardAndExit() }
            Button("Keep going", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showResults) {
            ResultsView(total: order.count, correct: correct) {
                showResults = false
                dismiss()
            }
        }
        .sheet(item: $editingCard) { card in
            if let cardDeck = card.deck {
                CardEditorSheet(deck: cardDeck, mode: .edit(card)) { front, back in
                    updateCard(card, front: front, back: back)
                }
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

    @ViewBuilder
    private var cardArea: some View {
        if index < order.count {
            FlashCard(
                card: order[index],
                inverted: inverted,
                isFlipped: isFlipped
            )
            .offset(x: dragOffset.width, y: dragOffset.height / 4)
            .rotationEffect(.degrees(Double(dragOffset.width) / 20))
            .overlay(alignment: .topLeading) {
                feedbackBadge(text: "WRONG", color: .red, visible: dragOffset.width < -20)
            }
            .overlay(alignment: .topTrailing) {
                feedbackBadge(text: "CORRECT", color: .green, visible: dragOffset.width > 20)
            }
            .onTapGesture {
                withAnimation(.spring(duration: 0.35)) {
                    isFlipped.toggle()
                }
            }
            .gesture(swipeGesture)
            .id(index)
        }
    }

    private func feedbackBadge(text: String, color: Color, visible: Bool) -> some View {
        Text(text)
            .font(.headline.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(12)
            .opacity(visible ? min(1, abs(dragOffset.width) / 80) : 0)
    }

    private var header: some View {
        HStack {
            Button("Cancel", role: .cancel) { showExitDialog = true }
            Spacer()
            Text("\(min(index + 1, max(order.count, 1))) / \(order.count)")
                .monospacedDigit()
                .font(.callout.weight(.medium))
            Spacer()
            Text("✓ \(correct)")
                .monospacedDigit()
                .font(.callout.weight(.medium))
                .foregroundStyle(.green)
            Button {
                guard index < order.count else { return }
                editingCard = order[index]
            } label: {
                Image(systemName: "pencil")
            }
            .accessibilityLabel("Edit card")
            .disabled(index >= order.count)
        }
    }

    private var footer: some View {
        Text(isFlipped ? "Swipe right if you knew it, left if not" : "Tap the card to reveal")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard isFlipped else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard isFlipped else { return }
                let threshold: CGFloat = 100
                if value.translation.width > threshold {
                    advance(wasCorrect: true)
                } else if value.translation.width < -threshold {
                    advance(wasCorrect: false)
                } else {
                    withAnimation(.spring()) { dragOffset = .zero }
                }
            }
    }

    private func buildOrder() {
        guard order.isEmpty else { return }
        if let paused = resume, let deck = deck {
            var byID: [UUID: Card] = [:]
            for card in deck.cards { byID[card.id] = card }
            order = paused.cardOrderIDs.compactMap { byID[$0] }
            index = min(paused.currentIndex, max(order.count - 1, 0))
            correct = paused.correct
            wrongIDs = paused.wrongCardIDs
            startedAt = paused.startedAt == .distantPast ? .now : paused.startedAt
        } else if case .global(let cards) = mode {
            // Caller supplies the sorted-by-overdueness list; just truncate.
            let limit = wordCount == 0 ? cards.count : min(wordCount, cards.count)
            order = Array(cards.prefix(limit))
        } else if let deck = deck, onlyHardest {
            let store = DifficultyStore.shared
            let scored: [(Card, Double)] = deck.cards.compactMap { card in
                guard let score = store.difficultyScore(deckName: deck.name, front: card.front, back: card.back), score > 0 else { return nil }
                return (card, score)
            }
            let sorted = scored.sorted { $0.1 > $1.1 }.map(\.0)
            let limit = wordCount == 0 ? sorted.count : min(wordCount, sorted.count)
            order = Array(sorted.prefix(limit))
            for card in order {
                card.wrongLastSession = false
            }
        } else if let deck = deck {
            let now = Date.now
            let calendar = Calendar.current
            let tomorrowStart = calendar.date(
                byAdding: .day, value: 1, to: calendar.startOfDay(for: now)
            ) ?? now

            let new = deck.cards.filter { $0.boxIndex == 0 }
            let scheduled = deck.cards.filter { $0.boxIndex >= 1 }
            let due = scheduled.filter { $0.nextDue < tomorrowStart }
            let undue = scheduled.filter { $0.nextDue >= tomorrowStart }

            // Shuffle first so ties on nextDue stay randomized; ascending sort puts most-overdue first.
            let dueSorted = due.shuffled().sorted { $0.nextDue < $1.nextDue }
            let combined = dueSorted + new.shuffled() + undue.shuffled()
            let limit = wordCount == 0 ? combined.count : min(wordCount, combined.count)
            order = Array(combined.prefix(limit))
            for card in order {
                card.wrongLastSession = false
            }
        }
    }

    private func advance(wasCorrect: Bool) {
        let card = order[index]
        card.wrongLastSession = !wasCorrect

        // Box/due is written exactly once per card per session — on the first grade.
        // Re-queued cards' subsequent grades only record DifficultyStore stats.
        if !gradedThisSession.contains(card.id) {
            let (box, due) = LeitnerScheduler.apply(
                grade: wasCorrect ? .good : .again,
                currentBox: card.boxIndex
            )
            card.boxIndex = box
            card.nextDue = due
            gradedThisSession.insert(card.id)
        }

        if wasCorrect {
            correct += 1
        } else if !wrongIDs.contains(card.id) {
            wrongIDs.append(card.id)
        }
        DifficultyStore.shared.recordAnswer(
            deckName: card.deck?.name ?? "",
            front: card.front,
            back: card.back,
            wasCorrect: wasCorrect
        )
        try? context.save()

        // Within-session reinforcement: re-queue an Again card up to `reinforcementCap` extra times.
        if !wasCorrect {
            let extras = againCountThisSession[card.id, default: 0]
            if extras < Self.reinforcementCap {
                order.append(card)
                againCountThisSession[card.id] = extras + 1
            }
        }

        withAnimation(.easeOut(duration: 0.25)) {
            dragOffset = CGSize(width: wasCorrect ? 600 : -600, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            dragOffset = .zero
            isFlipped = false
            if index + 1 >= order.count {
                if !isGlobal {
                    let result = SessionResult(
                        total: order.count,
                        correct: correct,
                        inverted: inverted,
                        startedAt: startedAt,
                        wrongCardIDs: wrongIDs
                    )
                    result.deck = deck
                    context.insert(result)
                    if let paused = resume {
                        context.delete(paused)
                    }
                    try? context.save()
                }
                showResults = true
            } else {
                index += 1
            }
        }
    }

    private func pauseAndExit() {
        guard let deck = deck else { dismiss(); return }
        if let paused = resume {
            paused.currentIndex = index
            paused.correct = correct
            paused.pausedAt = .now
            paused.wrongCardIDs = wrongIDs
            if paused.startedAt == .distantPast { paused.startedAt = startedAt }
        } else {
            let paused = PausedSession(
                cardOrderIDs: order.map { $0.id },
                currentIndex: index,
                correct: correct,
                inverted: inverted,
                wordCount: wordCount,
                startedAt: startedAt,
                wrongCardIDs: wrongIDs
            )
            paused.deck = deck
            context.insert(paused)
        }
        try? context.save()
        dismiss()
    }

    private func discardAndExit() {
        if let paused = resume {
            context.delete(paused)
            try? context.save()
        }
        dismiss()
    }

    private func updateCard(_ card: Card, front: String, back: String) {
        let oldFront = card.front
        let oldBack = card.back
        guard oldFront != front || oldBack != back else { return }
        card.front = front
        card.back = back
        try? context.save()
        guard let cardDeck = card.deck else { return }
        DifficultyStore.shared.rename(
            deckName: cardDeck.name,
            oldFront: oldFront, oldBack: oldBack,
            newFront: front, newBack: back
        )
        do {
            try DeckFileStore.write(cardDeck)
        } catch {
            fileError = error.localizedDescription
        }
    }
}

private struct FlashCard: View {
    let card: Card
    let inverted: Bool
    let isFlipped: Bool

    private var frontText: String { inverted ? card.back : card.front }
    private var backText: String { inverted ? card.front : card.back }

    var body: some View {
        ZStack {
            face(text: frontText, accent: false)
                .opacity(isFlipped ? 0 : 1)
            face(text: backText, accent: true)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 1 : 0)
        }
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .animation(.spring(duration: 0.45), value: isFlipped)
    }

    private func face(text: String, accent: Bool) -> some View {
        Text(text)
            .font(.system(size: 38, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.center)
            .padding(28)
            .frame(maxWidth: .infinity, minHeight: 320)
            .background(accent ? Color.accentColor.opacity(0.12) : Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(accent ? Color.accentColor.opacity(0.4) : Color.gray.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }
}
