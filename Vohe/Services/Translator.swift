import Foundation
import FoundationModels

/// Suggests a translation for a single vocabulary word using the on-device
/// Apple Intelligence model.
///
/// Every failure path collapses to `nil` — model unavailable, device not
/// eligible, language refused, empty answer. Callers treat `nil` as "no
/// suggestion, the user types it themselves", which is also what happens for
/// languages Apple doesn't officially support (Croatian among them).
enum Translator {
    @Generable
    struct Suggestion {
        @Guide(description: "The translation only — no explanation, quotes, or trailing punctuation")
        var translation: String
    }

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// A suggested translation of `text`, or `nil` when none can be produced.
    /// `source` and `target` are the deck's language names as the user wrote
    /// them in the file header (e.g. "Croatian", "Italian").
    static func translate(_ text: String, from source: String, to target: String) async -> String? {
        guard isAvailable else { return nil }
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return nil }

        let session = LanguageModelSession(
            instructions: """
                You translate single vocabulary words and short phrases for a flashcard app.
                Answer with the translation alone, in its dictionary form.
                If a word has several common translations, separate them with a comma.
                """
        )
        // The prompt is written in English and names the languages rather than
        // being written in them, which keeps the request inside the model's
        // supported-language envelope even when the word itself isn't.
        let prompt = "Translate the \(source) word \"\(word)\" into \(target)."

        do {
            let response = try await session.respond(to: prompt, generating: Suggestion.self)
            let cleaned = response.content.translation.trimmingCharacters(
                in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"."))
            )
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            return nil
        }
    }
}
