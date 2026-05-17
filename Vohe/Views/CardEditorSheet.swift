import SwiftUI

struct CardEditorSheet: View {
    enum Mode {
        case add
        case edit(Card)
    }

    let deck: Deck
    let mode: Mode
    let onCommit: (_ front: String, _ back: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var front: String = ""
    @State private var back: String = ""
    @FocusState private var focused: Field?

    private enum Field { case front, back }

    private var title: String {
        switch mode {
        case .add: return "Add Card"
        case .edit: return "Edit Card"
        }
    }

    private var saveDisabled: Bool {
        front.trimmingCharacters(in: .whitespaces).isEmpty ||
        back.trimmingCharacters(in: .whitespaces).isEmpty
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
                Section(deck.language2) {
                    TextField(deck.language2, text: $back)
                        .focused($focused, equals: .back)
                        .submitLabel(.done)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { commit() }
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
            .onAppear {
                if case .edit(let card) = mode {
                    front = card.front
                    back = card.back
                }
                focused = .front
            }
        }
    }

    private func commit() {
        let f = front.trimmingCharacters(in: .whitespaces)
        let b = back.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty, !b.isEmpty else { return }
        onCommit(f, b)
        dismiss()
    }
}
