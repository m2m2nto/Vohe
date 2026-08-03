import SwiftUI

struct CardEditorSheet: View {
    enum Mode {
        case add
        case edit(Card)
    }

    let deck: Deck
    let mode: Mode
    let onCommit: (_ front: String, _ back: String, _ needsValidation: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var front: String = ""
    @State private var back: String = ""
    @State private var isTranslating = false
    @State private var suggestion: String?
    @State private var lastTranslated: String?
    @FocusState private var focused: Field?

    private enum Field { case front, back }

    private var title: String {
        switch mode {
        case .add: return "Add Card"
        case .edit: return "Edit Card"
        }
    }

    private var isAdding: Bool {
        if case .add = mode { return true }
        return false
    }

    private var saveDisabled: Bool {
        front.trimmingCharacters(in: .whitespaces).isEmpty ||
        back.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// True when `back` is still exactly what the model proposed. Typing over
    /// the suggestion counts as validating it.
    private var isUnvalidatedSuggestion: Bool {
        guard let suggestion else { return false }
        return back.trimmingCharacters(in: .whitespaces) == suggestion
    }

    private var canSuggest: Bool {
        isAdding && Translator.isAvailable &&
        !front.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(deck.language1) {
                    TextField(deck.language1, text: $front)
                        .focused($focused, equals: .front)
                        .submitLabel(.next)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { focused = .back }
                }
                Section {
                    TextField(deck.language2, text: $back)
                        .focused($focused, equals: .back)
                        .submitLabel(.done)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { commit() }
                } header: {
                    Text(deck.language2)
                } footer: {
                    suggestionFooter
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { commit() }
                        .disabled(saveDisabled)
                }
            }
            .onChange(of: focused) { _, new in
                if new != .front { translateIfNeeded() }
            }
            .onAppear {
                if case .edit(let card) = mode {
                    front = card.front
                    back = card.back
                }
                focused = .front
            }
        }
    }

    @ViewBuilder
    private var suggestionFooter: some View {
        if isTranslating {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Suggesting a translation…")
            }
        } else if isUnvalidatedSuggestion {
            Label("Suggested on-device — check it before you trust it.", systemImage: "sparkles")
                .foregroundStyle(.orange)
        } else if canSuggest && back.trimmingCharacters(in: .whitespaces).isEmpty {
            Button("Suggest a translation") {
                lastTranslated = nil
                translateIfNeeded()
            }
        }
    }

    @MainActor
    private func translateIfNeeded() {
        guard canSuggest, !isTranslating else { return }
        let word = front.trimmingCharacters(in: .whitespaces)
        guard back.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard word != lastTranslated else { return }
        lastTranslated = word
        isTranslating = true
        Task { @MainActor in
            let result = await Translator.translate(
                word, from: deck.language1, to: deck.language2
            )
            isTranslating = false
            // Don't clobber anything typed while the model was thinking.
            guard let result, back.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            back = result
            suggestion = result
        }
    }

    private func commit() {
        let f = front.trimmingCharacters(in: .whitespaces)
        let b = back.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty, !b.isEmpty else { return }
        // Saving an edit is itself an act of validation.
        onCommit(f, b, isAdding && isUnvalidatedSuggestion)
        dismiss()
    }
}
