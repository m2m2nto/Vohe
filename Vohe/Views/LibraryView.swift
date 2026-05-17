import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]
    @Query(sort: \PausedSession.pausedAt, order: .reverse) private var paused: [PausedSession]
    @State private var reminderSettings: ReminderSettings = ReminderSettings.load()
    @State private var router = NotificationRouter.shared
    @State private var showingImporter = false
    @State private var importError: String?
    @State private var resumeTarget: PausedSession?
    @State private var quickSessionDeck: Deck?
    @State private var showingReminderSettings = false

    private static let pausedCap = 5

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
                        Image(systemName: reminderSettings.enabled ? "bell.fill" : "bell")
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
                ReminderSettingsSheet(settings: $reminderSettings)
            }
            .onAppear {
                Task { await refreshReminders() }
                handleQuickSessionRequest()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refreshReminders() } }
            }
            .onChange(of: router.quickSessionRequested) { _, _ in
                handleQuickSessionRequest()
            }
            .onChange(of: reminderSettings) { _, new in
                ReminderSettings.save(new)
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
            .fullScreenCover(item: $quickSessionDeck) { deck in
                SessionView(
                    deck: deck,
                    inverted: false,
                    wordCount: 5,
                    onlyHardest: false,
                    resume: nil
                )
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
            try? DeckFileStore.write(deck)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func deleteDecks(at offsets: IndexSet) {
        for idx in offsets {
            let deck = decks[idx]
            DeckFileStore.remove(deck)
            context.delete(deck)
        }
    }

    private func deletePaused(at offsets: IndexSet) {
        for idx in offsets {
            context.delete(paused[idx])
        }
    }

    private func refreshReminders() async {
        guard reminderSettings.enabled else {
            ReminderScheduler.cancelAll()
            return
        }
        await ReminderScheduler.reschedule(settings: reminderSettings, lastPracticedAt: lastSessionDate())
    }

    private func handleQuickSessionRequest() {
        guard router.quickSessionRequested else { return }
        router.quickSessionRequested = false
        guard paused.count < Self.pausedCap else { return }
        guard let deck = lastPracticedDeck(), !deck.cards.isEmpty else { return }
        quickSessionDeck = deck
    }

    private func lastPracticedDeck() -> Deck? {
        var descriptor = FetchDescriptor<SessionResult>(
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        if let last = try? context.fetch(descriptor).first, let deck = last.deck {
            return deck
        }
        return decks.first
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
    @Binding var settings: ReminderSettings
    @Environment(\.dismiss) private var dismiss
    @State private var permissionDenied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Daily reminders", isOn: $settings.enabled)
                } footer: {
                    Text("Days you've already practiced are skipped automatically.")
                }

                if settings.enabled {
                    Section {
                        Picker("Schedule", selection: $settings.mode) {
                            Text("Random").tag(ReminderSettings.Mode.random)
                            Text("Exact").tag(ReminderSettings.Mode.exact)
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("Schedule")
                    }

                    if settings.mode == .random {
                        randomSection
                    } else {
                        exactSection
                    }
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
            .onChange(of: settings.enabled) { _, enabled in
                guard enabled else {
                    permissionDenied = false
                    return
                }
                Task {
                    let granted = await ReminderScheduler.requestAuthorization()
                    await MainActor.run {
                        if !granted {
                            settings.enabled = false
                            permissionDenied = true
                        } else {
                            permissionDenied = false
                        }
                    }
                }
            }
        }
    }

    private var randomSection: some View {
        Section {
            Stepper(
                "Notifications per day: \(settings.count)",
                value: $settings.count,
                in: ReminderSettings.countRange
            )
            HStack {
                Text("From")
                Spacer()
                MinuteIntervalDatePicker(date: bindingForMinutes($settings.windowStartMinutes))
            }
            HStack {
                Text("To")
                Spacer()
                MinuteIntervalDatePicker(date: bindingForMinutes($settings.windowEndMinutes))
            }
        } header: {
            Text("Random window")
        } footer: {
            Text("Times are randomized each day inside this window.")
        }
    }

    private var exactSection: some View {
        Section {
            ForEach(Array(settings.exactTimesMinutes.enumerated()), id: \.offset) { idx, _ in
                HStack {
                    Text("Time \(idx + 1)")
                    Spacer()
                    MinuteIntervalDatePicker(date: bindingForMinutes(timeBinding(at: idx)))
                }
            }
            .onDelete { offsets in
                settings.exactTimesMinutes.remove(atOffsets: offsets)
                if settings.exactTimesMinutes.isEmpty {
                    settings.exactTimesMinutes = [9 * 60]
                }
            }
            if settings.exactTimesMinutes.count < ReminderSettings.countRange.upperBound {
                Button {
                    settings.exactTimesMinutes.append(12 * 60)
                } label: {
                    Label("Add Time", systemImage: "plus.circle.fill")
                }
            }
        } header: {
            Text("Exact times (\(settings.exactTimesMinutes.count))")
        } footer: {
            Text("Up to \(ReminderSettings.countRange.upperBound) fixed times per day. Swipe a row to delete.")
        }
    }

    private func timeBinding(at index: Int) -> Binding<Int> {
        Binding(
            get: { settings.exactTimesMinutes[index] },
            set: { settings.exactTimesMinutes[index] = $0 }
        )
    }

    private func bindingForMinutes(_ m: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Self.date(fromMinutes: m.wrappedValue) },
            set: { m.wrappedValue = Self.minutes(from: $0) }
        )
    }

    private static func date(fromMinutes m: Int) -> Date {
        Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
    }

    private static func minutes(from d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        let raw = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return (raw / 5) * 5
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
