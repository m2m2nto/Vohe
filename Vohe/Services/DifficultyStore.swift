import Foundation

struct CardStats: Codable {
    var seen: Int
    var wrong: Int
}

final class DifficultyStore {
    static let shared = DifficultyStore()

    static let minSeenForRanking = 3
    static let fileName = "difficulty.json"

    private var cache: [String: CardStats]

    private init() {
        cache = Self.load(from: Self.fileURL) ?? [:]
    }

    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    static func key(deckName: String, front: String, back: String) -> String {
        "\(deckName)\u{1F}\(front)\u{1F}\(back)"
    }

    private static func load(from url: URL) -> [String: CardStats]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([String: CardStats].self, from: data)
    }

    func recordAnswer(deckName: String, front: String, back: String, wasCorrect: Bool) {
        let k = Self.key(deckName: deckName, front: front, back: back)
        var s = cache[k] ?? CardStats(seen: 0, wrong: 0)
        s.seen += 1
        if !wasCorrect { s.wrong += 1 }
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
        let prefix = "\(oldName)\u{1F}"
        let staleKeys = cache.keys.filter { $0.hasPrefix(prefix) }
        guard !staleKeys.isEmpty else { return }
        for key in staleKeys {
            guard let stats = cache.removeValue(forKey: key) else { continue }
            let suffix = key.dropFirst(prefix.count)
            cache["\(newName)\u{1F}\(suffix)"] = stats
        }
        persist()
    }

    /// Returns wrong-rate when the card has been seen enough times; nil otherwise.
    func difficultyScore(deckName: String, front: String, back: String) -> Double? {
        guard let s = stats(deckName: deckName, front: front, back: back),
              s.seen >= Self.minSeenForRanking else { return nil }
        return Double(s.wrong) / Double(s.seen)
    }

    /// Count of cards in `deck` that have enough samples to participate in a "hardest" session.
    func rankableCount(deckName: String, fronts: [(front: String, back: String)]) -> Int {
        fronts.filter { (stats(deckName: deckName, front: $0.front, back: $0.back)?.seen ?? 0) >= Self.minSeenForRanking }.count
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
