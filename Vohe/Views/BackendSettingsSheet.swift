import SwiftUI

/// Address and account for the dictionary server. Signing in is the whole of
/// it: the password is typed here, sent once, and never stored — only the
/// session token that comes back is kept. Staying signed out keeps Vohe
/// entirely on-device.
struct BackendSettingsSheet: View {
    @Binding var settings: BackendSettings
    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var signingIn = false
    @State private var errorMessage: String?
    @State private var saveFailed = false

    private var signedIn: Bool { !settings.token.isEmpty }

    private var canSignIn: Bool {
        !address.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && !signingIn
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if signedIn {
                        Text(settings.address).foregroundStyle(.secondary)
                    } else {
                        TextField("https://your-dictionaries.vercel.app", text: $address)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                } header: {
                    Text("Server address")
                } footer: {
                    Text(signedIn
                         ? "Sign out to point Vohe at another server."
                         : "The web editor's address. Leave it empty to keep Vohe fully offline.")
                }

                if signedIn {
                    Section {
                        LabeledContent("Signed in as", value: settings.username)
                        Button("Sign out", role: .destructive) { signOut() }
                    } footer: {
                        Text("Signing out leaves every dictionary and everything you have learned on this device.")
                    }
                } else {
                    Section {
                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                        Button {
                            signIn()
                        } label: {
                            HStack {
                                Text("Sign in")
                                if signingIn {
                                    Spacer()
                                    ProgressView().controlSize(.mini)
                                }
                            }
                        }
                        .disabled(!canSignIn)
                    } header: {
                        Text("Account")
                    } footer: {
                        Text("The account an admin created for you. Only the session it returns is kept, in the iPhone keychain — never the password.")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if saveFailed {
                    Section {
                        Text("The sign-in couldn't be saved to the keychain.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Dictionary Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                address = settings.address
                username = settings.username
            }
        }
    }

    /// Nothing is written until the server has accepted the password, so a
    /// failed attempt leaves the stored settings exactly as they were.
    private func signIn() {
        signingIn = true
        errorMessage = nil
        saveFailed = false

        let draft = BackendSettings(
            address: address.trimmingCharacters(in: .whitespaces),
            username: username.trimmingCharacters(in: .whitespaces),
            token: ""
        )
        let typedPassword = password

        Task {
            do {
                let token = try await BackendClient(settings: draft).signIn(
                    username: draft.username,
                    password: typedPassword
                )
                var signedInSettings = draft
                signedInSettings.token = token
                if BackendSettings.save(signedInSettings) {
                    settings = BackendSettings.load()
                    password = ""
                    dismiss()
                } else {
                    saveFailed = true
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            signingIn = false
        }
    }

    /// Drops the token and keeps the address and the username, so signing back
    /// in is a password away.
    private func signOut() {
        var cleared = settings
        cleared.token = ""
        guard BackendSettings.save(cleared) else {
            saveFailed = true
            return
        }
        settings = BackendSettings.load()
        address = settings.address
        username = settings.username
        password = ""
        errorMessage = nil
    }
}
