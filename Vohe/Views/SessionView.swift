import SwiftUI
import SwiftData

struct SessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let deck: Deck
    let inverted: Bool
    let wordCount: Int
    let onlyHardest: Bool
    let resume: PausedSession?

    @State private var order: [Card] = []
    @State private var index = 0
    @State private var correct = 0
    @State private var wrongIDs: [UUID] = []
    @State private var startedAt: Date = .now
    @State private var isFlipped = false
    @State private var dragOffset: CGSize = .zero
    @State private var showResults = false
    @State private var showExitDialog = false

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
            Button("Pause") { pauseAndExit() }
            Button("Discard", role: .destructive) { discardAndExit() }
            Button("Keep going", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showResults) {
            ResultsView(total: order.count, correct: correct) {
                showResults = false
                dismiss()
            }
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
        if let paused = resume {
            var byID: [UUID: Card] = [:]
            for card in deck.cards { byID[card.id] = card }
            order = paused.cardOrderIDs.compactMap { byID[$0] }
            index = min(paused.currentIndex, max(order.count - 1, 0))
            correct = paused.correct
            wrongIDs = paused.wrongCardIDs
            startedAt = paused.startedAt == .distantPast ? .now : paused.startedAt
        } else if onlyHardest {
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
        } else {
            let wrong = deck.cards.filter { $0.wrongLastSession }.shuffled()
            let rest = deck.cards.filter { !$0.wrongLastSession }.shuffled()
            let combined = wrong + rest
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
        if wasCorrect {
            correct += 1
        } else {
            wrongIDs.append(card.id)
        }
        DifficultyStore.shared.recordAnswer(
            deckName: deck.name,
            front: card.front,
            back: card.back,
            wasCorrect: wasCorrect
        )

        withAnimation(.easeOut(duration: 0.25)) {
            dragOffset = CGSize(width: wasCorrect ? 600 : -600, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            dragOffset = .zero
            isFlipped = false
            if index + 1 >= order.count {
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
                showResults = true
            } else {
                index += 1
            }
        }
    }

    private func pauseAndExit() {
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
