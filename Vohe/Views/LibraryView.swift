import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]
    @Query(sort: \PausedSession.pausedAt, order: .reverse) private var paused: [PausedSession]
    @AppStorage(ReminderScheduler.userDefaultsKey) private var remindersEnabled = false
    @State private var showingImporter = false
    @State private var importError: String?
    @State private var resumeTarget: PausedSession?
    @State private var showingReminderSettings = false

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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingReminderSettings = true
                    } label: {
                        Image(systemName: remindersEnabled ? "bell.fill" : "bell")
                    }
                    .accessibilityLabel("Reminder settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Import deck")
                }
            }
            .sheet(isPresented: $showingReminderSettings) {
                ReminderSettingsSheet(remindersEnabled: $remindersEnabled)
            }
            .onAppear { Task { await refreshReminders() } }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refreshReminders() } }
            }
            .onChange(of: remindersEnabled) { _, _ in
                Task { await refreshReminders() }
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
                        onlyHardest: false,
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

    private func refreshReminders() async {
        guard remindersEnabled else {
            ReminderScheduler.cancelAll()
            return
        }
        await ReminderScheduler.reschedule(lastPracticedAt: lastSessionDate())
    }

    private func lastSessionDate() -> Date? {
        var descriptor = FetchDescriptor<SessionResult>(
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.completedAt
    }
}

private struct ReminderSettingsSheet: View {
    @Binding var remindersEnabled: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var permissionDenied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Daily reminders", isOn: $remindersEnabled)
                } footer: {
                    Text("Two gentle reminders per day at random times — one mid-morning, one in the evening. Days you've already practiced are skipped.")
                }
                if permissionDenied {
                    Section {
                        Text("Notifications are disabled for Vohe. Enable them in iOS Settings to receive reminders.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: remindersEnabled) { _, enabled in
                guard enabled else {
                    permissionDenied = false
                    return
                }
                Task {
                    let granted = await ReminderScheduler.requestAuthorization()
                    await MainActor.run {
                        if !granted {
                            remindersEnabled = false
                            permissionDenied = true
                        } else {
                            permissionDenied = false
                        }
                    }
                }
            }
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
