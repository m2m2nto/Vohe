import SwiftUI
import SwiftData

struct DeckDetailView: View {
    @Bindable var deck: Deck
    @State private var inverted = false
    @State private var sessionActive = false

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

            Section("Session") {
                Toggle("Inverted (show \(deck.language2) first)", isOn: $inverted)
                Button {
                    sessionActive = true
                } label: {
                    Label("Start Session", systemImage: "play.fill")
                }
                .disabled(deck.cards.isEmpty)
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
            SessionView(deck: deck, inverted: inverted)
        }
    }
}
