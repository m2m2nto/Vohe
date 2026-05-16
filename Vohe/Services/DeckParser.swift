import Foundation

enum DeckParser {
    struct ParsedDeck {
        let language1: String
        let language2: String
        let pairs: [(front: String, back: String)]
    }

    enum ParseError: LocalizedError {
        case empty
        case malformedHeader(String)
        case malformedLine(lineNumber: Int, content: String)
        case noCards

        var errorDescription: String? {
            switch self {
            case .empty:
                return "The file is empty."
            case .malformedHeader(let line):
                return "First line must be 'language1-language2'. Got: \"\(line)\""
            case .malformedLine(let n, let content):
                return "Line \(n) is not 'word-translation': \"\(content)\""
            case .noCards:
                return "No vocabulary entries found after the header."
            }
        }
    }

    static func parse(_ text: String) throws -> ParsedDeck {
        let rawLines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let usable = rawLines.enumerated().compactMap { idx, raw -> (Int, String)? in
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { return nil }
            return (idx + 1, trimmed)
        }

        guard let header = usable.first else { throw ParseError.empty }
        guard let (lang1, lang2) = splitOnFirstHyphen(header.1) else {
            throw ParseError.malformedHeader(header.1)
        }

        var pairs: [(front: String, back: String)] = []
        for (lineNumber, line) in usable.dropFirst() {
            guard let (front, back) = splitOnFirstHyphen(line) else {
                throw ParseError.malformedLine(lineNumber: lineNumber, content: line)
            }
            pairs.append((front, back))
        }

        guard !pairs.isEmpty else { throw ParseError.noCards }
        return ParsedDeck(language1: lang1, language2: lang2, pairs: pairs)
    }

    private static func splitOnFirstHyphen(_ s: String) -> (String, String)? {
        guard let idx = s.firstIndex(of: "-") else { return nil }
        let left = s[..<idx].trimmingCharacters(in: .whitespaces)
        let right = s[s.index(after: idx)...].trimmingCharacters(in: .whitespaces)
        guard !left.isEmpty, !right.isEmpty else { return nil }
        return (left, right)
    }
}
