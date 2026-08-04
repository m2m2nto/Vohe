import SwiftUI
import SwiftData

/// The dictionaries the backend offers. Adding one creates (or adopts) a local
/// deck; from then on the deck is linked and shows a badge when a newer version
/// is published.
struct RemoteDictionariesView: View {
    @Binding var settings: BackendSettings
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var decks: [Deck]

    @State private var catalog: [RemoteDictionarySummary] = []
    @State private var loading = false
    @State private var loadError: String?
    @State private var busyID: Int?
    @State private var actionError: String?
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if !settings.isConfigured {
                    ContentUnavailableView {
                        Label("No Dictionary Server", systemImage: "server.rack")
                    } description: {
                        Text("Add the server address and access token to browse shared dictionaries. Vohe works fully offline without one.")
                    } actions: {
                        Button("Server Settings") { showingSettings = true }
                    }
                } else if loading && catalog.isEmpty {
                    ProgressView("Loading dictionaries…")
                } else if let loadError, catalog.isEmpty {
                    ContentUnavailableView {
                        Label("Can't Load Dictionaries", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Try Again") { Task { await load() } }
                    }
                } else {
                    List {
                        if let loadError {
                            Section {
                                Text(loadError)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Section {
                            ForEach(catalog) { summary in
                                row(for: summary)
                            }
                        } footer: {
                            Text("Updating never removes anything from this device: words the dictionary no longer has stay, marked as only on this iPhone.")
                        }
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Dictionaries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Server settings")
                }
            }
            .sheet(isPresented: $showingSettings) {
                BackendSettingsSheet(settings: $settings)
            }
            .onChange(of: settings) { _, _ in
                Task { await load() }
            }
            .task { await load() }
            .alert(
                "Couldn't Update Dictionary",
                isPresented: Binding(
                    get: { actionError != nil },
                    set: { if !$0 { actionError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { actionError = nil }
            } message: {
                Text(actionError ?? "")
            }
        }
    }

    @ViewBuilder
    private func row(for summary: RemoteDictionarySummary) -> some View {
        let deck = DictionarySync.existingDeck(for: summary, in: decks)
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.name)
                    .font(.headline)
                Text("\(summary.language1) → \(summary.language2) · \(summary.wordCount) words · v\(summary.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if busyID == summary.id {
                ProgressView().controlSize(.small)
            } else if let deck, deck.isLinked, deck.syncedVersion >= summary.version {
                Text("Up to date")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button(deck == nil ? "Add" : "Update") {
                    Task { await pull(summary) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    private func load() async {
        guard settings.isConfigured else {
            catalog = []
            loadError = nil
            return
        }
        loading = true
        do {
            catalog = try await BackendClient(settings: settings).catalog()
            DictionarySync.noteCatalogVersions(catalog, in: decks)
            try? context.save()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        loading = false
    }

    private func pull(_ summary: RemoteDictionarySummary) async {
        busyID = summary.id
        defer { busyID = nil }
        do {
            let remote = try await BackendClient(settings: settings).dictionary(id: summary.id)
            let deck = DictionarySync.existingDeck(for: summary, in: decks) ?? {
                let created = Deck(
                    name: remote.name,
                    language1: remote.language1,
                    language2: remote.language2
                )
                context.insert(created)
                return created
            }()
            DictionarySync.apply(remote, to: deck, context: context)
            try? DeckFileStore.write(deck)
        } catch {
            actionError = error.localizedDescription
        }
    }
}
