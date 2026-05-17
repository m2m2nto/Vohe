import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]
    @Query(sort: \PausedSession.pausedAt, order: .reverse) private var paused: [PausedSession]
    @State private var showingImporter = false
    @State private var importError: String?
    @State private var resumeTarget: PausedSession?

    var body: some View {
        NavigationStack {
            Group {
                if decks.isEmpty && paused.isEmpty {
                    ContentUnavailableView(
                        "No Decks Yet",
                        systemImage: "books.vertical",
                        description: Text("Tap + to import a vocabulary file from iCloud Drive or Google Drive.")
                    )
                } else {
                    List {
                        if !paused.isEmpty {
                            Section("In Progress") {
                                ForEach(paused) { session in
                                    Button {
                                        resumeTarget = session
                                    } label: {
                                        PausedRow(session: session)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .onDelete(perform: deletePaused)
                            }
                        }
                        if !decks.isEmpty {
                            Section("Decks") {
                                ForEach(decks) { deck in
                                    NavigationLink(value: deck) {
                                        DeckRow(deck: deck)
                                    }
                                }
                                .onDelete(perform: deleteDecks)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Vohe")
            .navigationDestination(for: Deck.self) { deck in
                DeckDetailView(deck: deck)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Import deck")
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.plainText, .text, .utf8PlainText],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .alert(
                "Import Failed",
                isPresented: Binding(
                    get: { importError != nil },
                    set: { if !$0 { importError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .fullScreenCover(item: $resumeTarget) { session in
                if let deck = session.deck {
                    SessionView(
                        deck: deck,
                        inverted: session.inverted,
                        wordCount: session.wordCount,
                        resume: session
                    )
                }
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let text = try String(contentsOf: url, encoding: .utf8)
            let parsed = try DeckParser.parse(text)
            let name = url.deletingPathExtension().lastPathComponent
            let deck = Deck(name: name, language1: parsed.language1, language2: parsed.language2)
            context.insert(deck)
            for pair in parsed.pairs {
                let card = Card(front: pair.front, back: pair.back)
                card.deck = deck
                context.insert(card)
            }
            try context.save()
        } catch {
            importError = error.localizedDescription
        }
    }

    private func deleteDecks(at offsets: IndexSet) {
        for idx in offsets {
            context.delete(decks[idx])
        }
    }

    private func deletePaused(at offsets: IndexSet) {
        for idx in offsets {
            context.delete(paused[idx])
        }
    }
}

private struct DeckRow: View {
    let deck: Deck

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(deck.name)
                .font(.headline)
            HStack {
                Text("\(deck.language1) → \(deck.language2)")
                Spacer()
                Text("\(deck.cards.count) cards")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let last = deck.sessions.sorted(by: { $0.completedAt > $1.completedAt }).first {
                Text("Last: \(last.correct)/\(last.total)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct PausedRow: View {
    let session: PausedSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.deck?.name ?? "Deleted deck")
                    .font(.headline)
                HStack(spacing: 8) {
                    Text("\(session.currentIndex) / \(session.cardOrderIDs.count)")
                        .monospacedDigit()
                    Text("•")
                    Text("✓ \(session.correct)")
                        .monospacedDigit()
                        .foregroundStyle(.green)
                    if session.inverted {
                        Text("•")
                        Image(systemName: "arrow.left.arrow.right")
                            .accessibilityLabel("Inverted")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
