import SwiftUI
import SwiftData

struct DeckDetailView: View {
    @Bindable var deck: Deck
    @Environment(\.modelContext) private var context
    @Query private var allPaused: [PausedSession]
    @Query private var allDecks: [Deck]
    @State private var inverted = false
    @State private var wordCount: Int = 20
    @State private var sessionActive = false
    @State private var hardestActive = false
    @State private var showCapAlert = false
    @State private var addingCard = false
    @State private var fileError: String?
    @State private var renaming = false
    @State private var renameText = ""

    static let wordCountOptions: [(label: String, value: Int)] = [
        ("5", 5), ("20", 20), ("50", 50), ("100", 100), ("All", 0)
    ]
    static let pausedCap = 5

    private var rankableCount: Int {
        DifficultyStore.shared.rankableCount(
            deckName: deck.name,
            fronts: deck.cards.map { ($0.front, $0.back) }
        )
    }

    private var wrongCount: Int {
        deck.cards.filter { $0.wrongLastSession }.count
    }

    private var recentSessions: [SessionResult] {
        Array(deck.sessions.sorted(by: { $0.completedAt > $1.completedAt }).prefix(5))
    }

    var body: some View {
        Form {
            Section("Deck") {
                Button {
                    renameText = deck.name
                    renaming = true
                } label: {
                    LabeledContent("Name") {
                        Text(deck.name)
                            .foregroundStyle(.tint)
                    }
                }
                .buttonStyle(.plain)
                LabeledContent("Language pair") {
                    Text("\(deck.language1) → \(deck.language2)")
                }
                NavigationLink {
                    CardsListView(deck: deck)
                } label: {
                    LabeledContent("Cards") {
                        Text("\(deck.cards.count)")
                    }
                }
                if wrongCount > 0 {
                    NavigationLink {
                        WrongCardsView(deck: deck)
                    } label: {
                        LabeledContent("Wrong last session") {
                            Text("\(wrongCount)")
                                .foregroundStyle(.orange)
                        }
                    }
                } else {
                    LabeledContent("Wrong last session") {
                        Text("0")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Picker("Words", selection: $wordCount) {
                    ForEach(Self.wordCountOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Inverted (show \(deck.language2) first)", isOn: $inverted)
                Button {
                    if allPaused.count >= Self.pausedCap {
                        showCapAlert = true
                    } else {
                        sessionActive = true
                    }
                } label: {
                    Label("Start Session", systemImage: "play.fill")
                }
                .disabled(deck.cards.isEmpty)
                Button {
                    if allPaused.count >= Self.pausedCap {
                        showCapAlert = true
                    } else {
                        hardestActive = true
                    }
                } label: {
                    Label("Practice Hardest", systemImage: "flame.fill")
                }
                .disabled(rankableCount < DifficultyStore.minSeenForRanking)
            } header: {
                Text("Session")
            } footer: {
                if rankableCount < DifficultyStore.minSeenForRanking {
                    Text("Practice Hardest unlocks once you've seen at least \(DifficultyStore.minSeenForRanking) cards three or more times.")
                }
            }

            Section("Recent Results") {
                if recentSessions.isEmpty {
                    Text("No sessions yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentSessions) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            HStack {
                                Text(session.completedAt, format: .dateTime.month().day().hour().minute())
                                Spacer()
                                if session.inverted {
                                    Image(systemName: "arrow.left.arrow.right")
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel("Inverted session")
                                }
                                Text("\(session.correct)/\(session.total)")
                                    .monospacedDigit()
                            }
                            .font(.callout)
                        }
                    }
                }
            }
        }
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { addingCard = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add card")
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: DeckFileStore.url(for: deck)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Export deck file")
            }
        }
        .onAppear {
            try? DeckFileStore.writeIfMissing(deck)
        }
        .sheet(isPresented: $addingCard) {
            CardEditorSheet(deck: deck, mode: .add) { front, back in
                addCard(front: front, back: back)
            }
        }
        .fullScreenCover(isPresented: $sessionActive) {
            SessionView(deck: deck, inverted: inverted, wordCount: wordCount, onlyHardest: false, resume: nil)
        }
        .fullScreenCover(isPresented: $hardestActive) {
            SessionView(deck: deck, inverted: inverted, wordCount: wordCount, onlyHardest: true, resume: nil)
        }
        .alert("Too Many Paused Sessions", isPresented: $showCapAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You have \(Self.pausedCap) paused sessions. Resume or discard one from the Library to start a new one.")
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
        .alert("Rename Deck", isPresented: $renaming) {
            TextField("Deck name", text: $renameText)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Save") { renameDeck() }
                .disabled(renameInvalid)
        } message: {
            Text(nameIsTaken ? "Another deck already uses that name." : "Enter a new name for this deck.")
        }
    }

    private var trimmedRenameText: String {
        renameText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nameIsTaken: Bool {
        let name = trimmedRenameText
        return !name.isEmpty && allDecks.contains { $0.id != deck.id && $0.name == name }
    }

    private var renameInvalid: Bool {
        trimmedRenameText.isEmpty || nameIsTaken
    }

    private func renameDeck() {
        let newName = trimmedRenameText
        let oldName = deck.name
        guard !newName.isEmpty, newName != oldName, !nameIsTaken else { return }
        deck.name = newName
        try? context.save()
        DifficultyStore.shared.renameDeck(from: oldName, to: newName)
        do {
            try DeckFileStore.rename(deck, from: oldName)
        } catch {
            fileError = error.localizedDescription
        }
    }

    private func addCard(front: String, back: String) {
        let card = Card(front: front, back: back)
        card.deck = deck
        context.insert(card)
        try? context.save()
        do {
            try DeckFileStore.write(deck)
        } catch {
            fileError = error.localizedDescription
        }
    }
}
