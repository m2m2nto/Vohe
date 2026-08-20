import SwiftUI

/// Lists how long each card takes to answer, so a "learned" threshold can be
/// read off real numbers before anything acts on it. Nothing here changes what
/// a session shows — it only reports.
struct ReactionTimesView: View {
    enum Sort: String, CaseIterable, Identifiable {
        case swipe = "Swipe"
        case flip = "Flip"
        case times = "Times"

        var id: String { rawValue }

        /// What this sort puts at the top, named for the footer.
        var orderNote: String {
            switch self {
            case .swipe, .flip: return "Fastest first."
            case .times: return "Most times first."
            }
        }
    }

    @State private var timings: [CardTiming] = []
    @State private var sort: Sort = .swipe

    private var sorted: [CardTiming] {
        switch sort {
        case .swipe: return timings.sorted { $0.averageSwipeSeconds < $1.averageSwipeSeconds }
        case .flip: return timings.sorted { $0.averageFlipSeconds < $1.averageFlipSeconds }
        case .times: return timings.sorted { $0.times > $1.times }
        }
    }

    var body: some View {
        Group {
            if timings.isEmpty {
                ContentUnavailableView(
                    "No Timings Yet",
                    systemImage: "stopwatch",
                    description: Text("A card is timed the first time it comes up in a session and you swipe it right. Finish a session and its cards show up here.")
                )
            } else {
                List {
                    Section {
                        Picker("Sort by", selection: $sort) {
                            ForEach(Sort.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    } footer: {
                        Text("Flip is how long the card sat before you revealed it; swipe is how long the call took after. Only each session's first showing of a card counts. \(sort.orderNote)")
                    }
                    Section("\(timings.count) cards") {
                        ForEach(sorted) { timing in
                            TimingRow(timing: timing)
                        }
                    }
                }
            }
        }
        .navigationTitle("Reaction Times")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { timings = DifficultyStore.shared.timedCards() }
    }
}

private struct TimingRow: View {
    let timing: CardTiming

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(timing.front) → \(timing.back)")
                .font(.headline)
            HStack(spacing: 8) {
                Text(timing.deckName)
                Spacer()
                Label(Self.seconds(timing.averageFlipSeconds), systemImage: "arrow.2.squarepath")
                Label(Self.seconds(timing.averageSwipeSeconds), systemImage: "hand.draw")
                Text("×\(timing.times)")
            }
            .labelStyle(TightLabelStyle())
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private static func seconds(_ value: Double) -> String {
        String(format: "%.2fs", value)
    }
}

/// The stock label style reserves a column for the icon inside a list row,
/// which leaves each symbol floating away from the value it belongs to.
private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}
