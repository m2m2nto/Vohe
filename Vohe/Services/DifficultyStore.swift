import Foundation

struct CardStats: Codable {
    var seen: Int
    var wrong: Int
    /// Timed samples. Only a Good grade is sampled, so the averages describe
    /// recall the user actually got right.
    var timed: Int = 0
    /// Seconds from the card appearing to its reveal, summed over `timed`.
    var flipSeconds: Double = 0
    /// Seconds from the reveal to the swipe, summed over `timed`.
    var swipeSeconds: Double = 0
}

/// `difficulty.json` predates the timing fields, so a file written by an
/// earlier build decodes with no samples rather than failing outright.
extension CardStats {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seen = try c.decode(Int.self, forKey: .seen)
        wrong = try c.decode(Int.self, forKey: .wrong)
        timed = try c.decodeIfPresent(Int.self, forKey: .timed) ?? 0
        flipSeconds = try c.decodeIfPresent(Double.self, forKey: .flipSeconds) ?? 0
        swipeSeconds = try c.decodeIfPresent(Double.self, forKey: .swipeSeconds) ?? 0
    }
}

/// One card's reaction times, as the metrics screen lists them.
struct CardTiming: Identifiable {
    let deckName: String
    let front: String
    let back: String
    let times: Int
    let averageFlipSeconds: Double
    let averageSwipeSeconds: Double

    var id: String { DifficultyStore.key(deckName: deckName, front: front, back: back) }
}

final class DifficultyStore {
    static let shared = DifficultyStore()

    static let minSeenForRanking = 3
    static let fileName = "difficulty.json"
    /// Joins the three parts of a cache key. Unit Separator — an ASCII control
    /// character no deck name or card text carries, so no key is ambiguous.
    private static let separator = "\u{1F}"

    private var cache: [String: CardStats]

    private init() {
        cache = Self.load(from: Self.fileURL) ?? [:]
    }

    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    static func key(deckName: String, front: String, back: String) -> String {
        "\(deckName)\(separator)\(front)\(separator)\(back)"
    }

    private static func load(from url: URL) -> [String: CardStats]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([String: CardStats].self, from: data)
    }

    /// Records one grade. `timing` is supplied only when the session could time
    /// the answer end to end; without it the grade still counts towards `seen`
    /// and `wrong` but not the averages.
    func recordAnswer(
        deckName: String,
        front: String,
        back: String,
        wasCorrect: Bool,
        timing: (flip: TimeInterval, swipe: TimeInterval)? = nil
    ) {
        let k = Self.key(deckName: deckName, front: front, back: back)
        var s = cache[k] ?? CardStats(seen: 0, wrong: 0)
        s.seen += 1
        if !wasCorrect { s.wrong += 1 }
        if let timing {
            s.timed += 1
            s.flipSeconds += timing.flip
            s.swipeSeconds += timing.swipe
        }
        cache[k] = s
        persist()
    }

    func stats(deckName: String, front: String, back: String) -> CardStats? {
        cache[Self.key(deckName: deckName, front: front, back: back)]
    }

    func remove(deckName: String, front: String, back: String) {
        let k = Self.key(deckName: deckName, front: front, back: back)
        guard cache.removeValue(forKey: k) != nil else { return }
        persist()
    }

    func rename(deckName: String, oldFront: String, oldBack: String, newFront: String, newBack: String) {
        let oldKey = Self.key(deckName: deckName, front: oldFront, back: oldBack)
        let newKey = Self.key(deckName: deckName, front: newFront, back: newBack)
        guard oldKey != newKey, let stats = cache.removeValue(forKey: oldKey) else { return }
        cache[newKey] = stats
        persist()
    }

    /// Migrates every card stat from `oldName` to `newName` after a deck rename.
    func renameDeck(from oldName: String, to newName: String) {
        guard oldName != newName else { return }
        let prefix = "\(oldName)\(Self.separator)"
        let staleKeys = cache.keys.filter { $0.hasPrefix(prefix) }
        guard !staleKeys.isEmpty else { return }
        for key in staleKeys {
            guard let stats = cache.removeValue(forKey: key) else { continue }
            let suffix = key.dropFirst(prefix.count)
            cache["\(newName)\(Self.separator)\(suffix)"] = stats
        }
        persist()
    }

    /// Returns wrong-rate when the card has been seen enough times; nil otherwise.
    func difficultyScore(deckName: String, front: String, back: String) -> Double? {
        guard let s = stats(deckName: deckName, front: front, back: back),
              s.seen >= Self.minSeenForRanking else { return nil }
        return Double(s.wrong) / Double(s.seen)
    }

    /// Count of cards a "hardest" session would actually drill: enough samples to
    /// rank, and a wrong-rate above 0. Mirrors the filter in `SessionView.buildOrder`,
    /// so a zero count means the session would be empty.
    func hardestCount(deckName: String, fronts: [(front: String, back: String)]) -> Int {
        fronts.filter { (difficultyScore(deckName: deckName, front: $0.front, back: $0.back) ?? 0) > 0 }.count
    }

    /// Every card carrying at least one timed sample, across all decks. Keys
    /// outlive the cards they came from (a deleted deck leaves its stats
    /// behind), so this lists what was measured, not what still exists.
    func timedCards() -> [CardTiming] {
        cache.compactMap { key, stats in
            guard stats.timed > 0 else { return nil }
            let parts = key.components(separatedBy: Self.separator)
            guard parts.count == 3 else { return nil }
            return CardTiming(
                deckName: parts[0],
                front: parts[1],
                back: parts[2],
                times: stats.timed,
                averageFlipSeconds: stats.flipSeconds / Double(stats.timed),
                averageSwipeSeconds: stats.swipeSeconds / Double(stats.timed)
            )
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
