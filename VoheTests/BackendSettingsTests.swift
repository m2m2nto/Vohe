import XCTest
@testable import Vohe

/// The build-time defaults must stand in only until the user saves Server
/// settings once — after that, whatever they chose wins, including blank.
final class BackendSettingsTests: XCTestCase {
    private let editedKey = "vohe.backendSettingsEdited"
    private let addressKey = BackendSettings.addressKey
    private let usernameKey = BackendSettings.usernameKey

    override func setUp() {
        clearStoredSettings()
    }

    override func tearDown() {
        clearStoredSettings()
    }

    private func clearStoredSettings() {
        BackendSettings.save(.empty) // also empties the keychain slot
        UserDefaults.standard.removeObject(forKey: editedKey)
        UserDefaults.standard.removeObject(forKey: addressKey)
        UserDefaults.standard.removeObject(forKey: usernameKey)
    }

    func testUntouchedSettingsStartFromTheBuildTimeDefaults() {
        XCTAssertEqual(BackendSettings.load().address, BackendDefaults.address)
    }

    func testASavedBlankStaysBlank() {
        UserDefaults.standard.set(true, forKey: editedKey)
        XCTAssertEqual(BackendSettings.load().address, "")
    }

    func testASavedAddressWins() {
        UserDefaults.standard.set(true, forKey: editedKey)
        UserDefaults.standard.set("https://example.test", forKey: addressKey)
        XCTAssertEqual(BackendSettings.load().address, "https://example.test")
    }

    func testOnlyHttpAndHttpsAddressesAreUsable() {
        let usable = { (address: String) in
            BackendSettings(address: address, username: "u", token: "t").url?.absoluteString
        }
        XCTAssertEqual(usable("https://vohe.test/"), "https://vohe.test")
        XCTAssertEqual(usable("  https://vohe.test/api/  "), "https://vohe.test/api")
        XCTAssertNil(usable(""))
        XCTAssertNil(usable("vohe.test"), "a bare host has no scheme to trust")
        XCTAssertNil(usable("ftp://vohe.test"))
        XCTAssertFalse(
            BackendSettings(address: "https://vohe.test", username: "u", token: " ").isConfigured
        )
        XCTAssertTrue(
            BackendSettings(address: "https://vohe.test", username: "u", token: "t").isConfigured
        )
    }

    /// The username is a preference like the address; the token is not, and
    /// signing out has to leave the keychain empty rather than remembered.
    func testUsernameIsRemembered() {
        XCTAssertTrue(
            BackendSettings.save(
                BackendSettings(address: "https://vohe.test", username: "ada", token: "t")
            )
        )
        var loaded = BackendSettings.load()
        XCTAssertEqual(loaded.username, "ada")
        XCTAssertEqual(loaded.token, "t")
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: usernameKey), "ada",
            "the username belongs in UserDefaults, not the keychain"
        )

        // Signing out: the token goes, the address and the username stay.
        XCTAssertTrue(
            BackendSettings.save(
                BackendSettings(address: "https://vohe.test", username: "ada", token: "")
            )
        )
        loaded = BackendSettings.load()
        XCTAssertEqual(loaded.token, "")
        XCTAssertEqual(loaded.username, "ada")
        XCTAssertEqual(loaded.address, "https://vohe.test")
        XCTAssertFalse(loaded.isConfigured)
    }

    /// A signed-out install must not resurrect a token from the build-time
    /// defaults — there is no longer one to resurrect.
    func testNoTokenIsEverInherited() {
        XCTAssertEqual(BackendSettings.load().token, "")
    }
}
