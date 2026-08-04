import XCTest
@testable import Vohe

/// The build-time defaults must stand in only until the user saves Server
/// settings once — after that, whatever they chose wins, including blank.
final class BackendSettingsTests: XCTestCase {
    private let editedKey = "vohe.backendSettingsEdited"
    private let addressKey = BackendSettings.addressKey

    override func setUp() {
        UserDefaults.standard.removeObject(forKey: editedKey)
        UserDefaults.standard.removeObject(forKey: addressKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: editedKey)
        UserDefaults.standard.removeObject(forKey: addressKey)
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
            BackendSettings(address: address, token: "t").url?.absoluteString
        }
        XCTAssertEqual(usable("https://vohe.test/"), "https://vohe.test")
        XCTAssertEqual(usable("  https://vohe.test/api/  "), "https://vohe.test/api")
        XCTAssertNil(usable(""))
        XCTAssertNil(usable("vohe.test"), "a bare host has no scheme to trust")
        XCTAssertNil(usable("ftp://vohe.test"))
        XCTAssertFalse(BackendSettings(address: "https://vohe.test", token: " ").isConfigured)
        XCTAssertTrue(BackendSettings(address: "https://vohe.test", token: "t").isConfigured)
    }
}
