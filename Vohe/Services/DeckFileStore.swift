import Foundation

enum DeckFileStore {
    static let directoryName = "Decks"

    static var directoryURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    static func url(forDeckNamed name: String) -> URL {
        directoryURL.appendingPathComponent(sanitize(name) + ".txt", isDirectory: false)
    }

    static func url(for deck: Deck) -> URL {
        url(forDeckNamed: deck.name)
    }

    static func write(_ deck: Deck) throws {
        try ensureDirectory()
        let body = serialize(deck)
        try body.data(using: .utf8)?.write(to: url(for: deck), options: .atomic)
    }

    static func writeIfMissing(_ deck: Deck) throws {
        let target = url(for: deck)
        if FileManager.default.fileExists(atPath: target.path) { return }
        try write(deck)
    }

    static func remove(deckNamed name: String) {
        try? FileManager.default.removeItem(at: url(forDeckNamed: name))
    }

    static func remove(_ deck: Deck) {
        remove(deckNamed: deck.name)
    }

    /// Rewrites the mirror file under the deck's current name and deletes the
    /// stale file from `oldName` (skipped when both sanitize to the same path).
    static func rename(_ deck: Deck, from oldName: String) throws {
        try write(deck)
        let oldURL = url(forDeckNamed: oldName)
        if oldURL != url(for: deck) {
            try? FileManager.default.removeItem(at: oldURL)
        }
    }

    private static func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private static func serialize(_ deck: Deck) -> String {
        var lines: [String] = ["\(deck.language1)-\(deck.language2)"]
        for card in deck.cards {
            lines.append("\(card.front) - \(card.back)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func sanitize(_ name: String) -> String {
        let illegal: Set<Character> = ["/", "\\", ":", "\0"]
        let cleaned = String(name.map { illegal.contains($0) ? "_" : $0 })
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Deck" : trimmed
    }
}
