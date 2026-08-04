import Foundation

/// Where the dictionary backend lives and how to prove we may read it.
///
/// The address is a plain preference; the token is a credential and lives in
/// the keychain. Nothing here is required — with no address or no token the app
/// simply never talks to a backend and behaves exactly as it always did.
struct BackendSettings: Equatable {
    var address: String
    var token: String

    static let addressKey = "vohe.backendAddress"
    /// Set the first time the user saves, so clearing a field stays cleared
    /// instead of falling back to `BackendDefaults`.
    private static let editedKey = "vohe.backendSettingsEdited"
    private static let keychainService = "com.danilo.vohe.backend"
    private static let keychainAccount = "apiToken"

    static let empty = BackendSettings(address: "", token: "")

    /// The catalog root, or nil when the address isn't a usable https/http URL.
    var url: URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var text = trimmed
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil
        else { return nil }
        return url
    }

    var isConfigured: Bool {
        url != nil && !token.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Until the user saves Server settings once, the build-time defaults stand
    /// in — so a fresh install can connect without typing a long token.
    static func load() -> BackendSettings {
        let edited = UserDefaults.standard.bool(forKey: editedKey)
        return BackendSettings(
            address: UserDefaults.standard.string(forKey: addressKey)
                ?? (edited ? "" : BackendDefaults.address),
            token: loadToken() ?? (edited ? "" : BackendDefaults.token)
        )
    }

    /// Returns false when the keychain refused the token, so the UI can say so
    /// instead of silently forgetting it.
    @discardableResult
    static func save(_ settings: BackendSettings) -> Bool {
        UserDefaults.standard.set(settings.address, forKey: addressKey)
        UserDefaults.standard.set(true, forKey: editedKey)
        return saveToken(settings.token.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Keychain

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
    }

    private static func loadToken() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func saveToken(_ token: String) -> Bool {
        guard !token.isEmpty else {
            let status = SecItemDelete(baseQuery as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let data = Data(token.utf8)
        let updated = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }

        var insert = baseQuery
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }
}
