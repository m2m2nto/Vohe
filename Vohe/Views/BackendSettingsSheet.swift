import SwiftUI

/// Address and access token for the dictionary server. Leaving either empty
/// keeps the app entirely on-device.
struct BackendSettingsSheet: View {
    @Binding var settings: BackendSettings
    @Environment(\.dismiss) private var dismiss

    @State private var draft: BackendSettings = .empty
    @State private var testing = false
    @State private var testResult: String?
    @State private var testFailed = false
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://your-dictionaries.vercel.app", text: $draft.address)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Server address")
                } footer: {
                    Text("The web editor's address. Leave it empty to keep Vohe fully offline.")
                }

                Section {
                    SecureField("Access token", text: $draft.token)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Access token")
                } footer: {
                    Text("The API_TOKEN set on the server. Stored in the iPhone keychain.")
                }

                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Text("Test connection")
                            if testing {
                                Spacer()
                                ProgressView().controlSize(.mini)
                            }
                        }
                    }
                    .disabled(!draft.isConfigured || testing)
                    if let testResult {
                        Text(testResult)
                            .font(.footnote)
                            .foregroundStyle(testFailed ? .red : .green)
                    }
                }

                if saveFailed {
                    Section {
                        Text("The token couldn't be saved to the keychain.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Dictionary Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                }
            }
            .onAppear { draft = settings }
        }
    }

    private func save() {
        guard BackendSettings.save(draft) else {
            saveFailed = true
            return
        }
        settings = BackendSettings.load()
        dismiss()
    }

    private func testConnection() {
        testing = true
        testResult = nil
        Task {
            do {
                let catalog = try await BackendClient(settings: draft).catalog()
                testFailed = false
                testResult = "Connected — \(catalog.count) dictionaries available."
            } catch {
                testFailed = true
                testResult = error.localizedDescription
            }
            testing = false
        }
    }
}
