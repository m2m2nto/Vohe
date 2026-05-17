import SwiftUI
import SwiftData

struct DeckDetailView: View {
    @Bindable var deck: Deck
    @Query private var allPaused: [PausedSession]
    @State private var inverted = false
    @State private var wordCount: Int = 20
    @State private var sessionActive = false
    @State private var hardestActive = false
    @State private var showCapAlert = false

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
                LabeledContent("Language pair") {
                    Text("\(deck.language1) → \(deck.language2)")
                }
                LabeledContent("Cards") {
                    Text("\(deck.cards.count)")
                }
                LabeledContent("Wrong last session") {
                    Text("\(wrongCount)")
                        .foregroundStyle(wrongCount > 0 ? .orange : .secondary)
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
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
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
    }
}
