import SwiftUI
import SwiftData

struct DeckDetailView: View {
    @Bindable var deck: Deck
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allDecks: [Deck]
    @State private var inverted = false
    @State private var wordCount: Int = 20
    @State private var sessionActive = false
    @State private var hardestActive = false
    @State private var addingCard = false
    @State private var fileError: String?
    @State private var renaming = false
    @State private var renameText = ""
    @State private var backendSettings = BackendSettings.load()
    @State private var syncing = false
    @State private var syncMessage: String?
    @State private var confirmingDelete = false

    static let wordCountOptions: [(label: String, value: Int)] = [
        ("5", 5), ("20", 20), ("50", 50), ("100", 100), ("All", 0)
    ]

    private var hardestCount: Int {
        DifficultyStore.shared.hardestCount(
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

    private var unsubmittedCards: [Card] {
        DictionarySync.cardsNeedingSubmission(in: deck)
    }

    /// What a tap on "Send for review" would carry — nothing, once every word
    /// has been sent and is waiting.
    private var sendableCards: [Card] {
        DictionarySync.cardsToSubmit(in: deck)
    }

    private var awaitingReviewCount: Int {
        DictionarySync.cardsAwaitingReview(in: deck).count
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

            if deck.isLinked {
                dictionarySection
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
                    UserDefaults.standard.set(wordCount, forKey: "vohe.lastSlotSize")
                    sessionActive = true
                } label: {
                    Label("Start Session", systemImage: "play.fill")
                }
                .disabled(deck.cards.isEmpty)
                Button {
                    UserDefaults.standard.set(wordCount, forKey: "vohe.lastSlotSize")
                    hardestActive = true
                } label: {
                    Label("Practice Hardest", systemImage: "flame.fill")
                }
                .disabled(hardestCount == 0)
            } header: {
                Text("Session")
            } footer: {
                if hardestCount == 0 {
                    Text("Practice Hardest unlocks once you've missed a card you've seen \(DifficultyStore.minSeenForRanking) or more times.")
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

            Section {
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("Delete Deck", systemImage: "trash")
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
            CardEditorSheet(deck: deck, mode: .add) { front, back, needsValidation in
                addCard(front: front, back: back, needsValidation: needsValidation)
            }
        }
        .fullScreenCover(isPresented: $sessionActive) {
            SessionView(deck: deck, inverted: inverted, wordCount: wordCount, onlyHardest: false, resume: nil)
        }
        .fullScreenCover(isPresented: $hardestActive) {
            SessionView(deck: deck, inverted: inverted, wordCount: wordCount, onlyHardest: true, resume: nil)
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
        .alert(
            "Shared Dictionary",
            isPresented: Binding(
                get: { syncMessage != nil },
                set: { if !$0 { syncMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { syncMessage = nil }
        } message: {
            Text(syncMessage ?? "")
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
        .confirmationDialog(
            "Delete \"\(deck.name)\"?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Deck", role: .destructive) { deleteDeck() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteWarning)
        }
    }

    private var deleteWarning: String {
        let count = deck.cards.count
        var text = "\(count) card\(count == 1 ? "" : "s"), their practice history and any paused session are removed from this iPhone."
        if deck.isLinked {
            text += " The shared dictionary on the server is not affected."
        }
        return text
    }

    /// Removes the deck from this device only — same operation as swiping the
    /// row away in Library. Popping first keeps this view from redrawing a deck
    /// that no longer exists.
    private func deleteDeck() {
        dismiss()
        DeckFileStore.remove(deck)
        context.delete(deck)
    }

    /// Everything the shared dictionary adds to a deck: where its words came
    /// from, whether a newer version is waiting, and what this device has that
    /// the dictionary doesn't.
    @ViewBuilder
    private var dictionarySection: some View {
        Section {
            LabeledContent("Version") {
                if syncing {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("v\(deck.syncedVersion)")
                }
            }
            if deck.updateAvailable {
                Button {
                    Task { await updateFromDictionary() }
                } label: {
                    Label("Update to v\(deck.latestRemoteVersion)", systemImage: "arrow.down.circle")
                }
                .disabled(syncing)
            }
            if !unsubmittedCards.isEmpty {
                Button {
                    Task { await sendForReview() }
                } label: {
                    Label(sendButtonTitle, systemImage: "paperplane")
                        // Without this the symbol keeps its tint while the title
                        // greys out, and a dead button still reads as live.
                        .foregroundStyle(sendDisabled ? Color.secondary : Color.accentColor)
                }
                .disabled(sendDisabled)
            }
        } header: {
            Text("Shared dictionary")
        } footer: {
            Text(dictionaryFooter)
        }
    }

    /// Nothing new to send, or nothing that could be sent right now.
    private var sendDisabled: Bool {
        syncing || sendableCards.isEmpty || !backendSettings.isConfigured
    }

    /// Reads "Send N words for review" while there is something new to send, and
    /// states the waiting instead once the button has nothing left to carry.
    private var sendButtonTitle: String {
        let count = sendableCards.count
        guard count > 0 else { return "All words sent for review" }
        return "Send \(count) word\(count == 1 ? "" : "s") for review"
    }

    private var dictionaryFooter: String {
        var lines: [String] = []
        if !sendableCards.isEmpty {
            lines.append("\(sendableCards.count) word\(sendableCards.count == 1 ? " is" : "s are") only on this iPhone, or changed here. Sending them asks for them to be reviewed before they join the dictionary.")
        }
        if awaitingReviewCount > 0 {
            lines.append("\(awaitingReviewCount) waiting for review — an update leaves those untouched.")
        }
        lines.append("Updating replaces translations you changed here unless you send them for review first. Nothing is ever deleted from this device.")
        return lines.joined(separator: "\n\n")
    }

    private func updateFromDictionary() async {
        guard let id = deck.remoteID else { return }
        syncing = true
        defer { syncing = false }
        do {
            let remote = try await BackendClient(settings: backendSettings).dictionary(id: id)
            let report = DictionarySync.apply(remote, to: deck, context: context)
            try? DeckFileStore.write(deck)
            var parts = ["Updated to v\(remote.version)."]
            if report.added > 0 { parts.append("\(report.added) new.") }
            if report.updated > 0 { parts.append("\(report.updated) re-translated.") }
            if report.approved > 0 { parts.append("\(report.approved) of yours approved.") }
            if report.localOnly > 0 { parts.append("\(report.localOnly) only on this iPhone.") }
            syncMessage = parts.joined(separator: " ")
        } catch {
            syncMessage = error.localizedDescription
        }
    }

    private func sendForReview() async {
        guard let id = deck.remoteID else { return }
        let cards = sendableCards
        guard !cards.isEmpty else { return }
        syncing = true
        defer { syncing = false }
        do {
            let receipt = try await BackendClient(settings: backendSettings).submit(
                cards.map { RemoteWord(word: $0.front, translation: $0.back) },
                toDictionary: id
            )
            DictionarySync.markSubmitted(cards)
            try? context.save()
            var parts = ["\(receipt.accepted) sent for review."]
            if receipt.alreadyPending > 0 { parts.append("\(receipt.alreadyPending) already waiting.") }
            if !receipt.invalid.isEmpty {
                parts.append("\(receipt.invalid.count) can't be shared: \(receipt.invalid[0].reason)")
            }
            syncMessage = parts.joined(separator: " ")
        } catch {
            syncMessage = error.localizedDescription
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

    private func addCard(front: String, back: String, needsValidation: Bool) {
        let card = Card(front: front, back: back)
        card.needsValidation = needsValidation
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
