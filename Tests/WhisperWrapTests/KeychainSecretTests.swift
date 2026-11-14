import XCTest
@testable import WhisperWrap

@MainActor
final class KeychainSecretTests: XCTestCase {
    private let account = "test-\(UUID().uuidString)"
    private var savedWriter: (@MainActor (String, String) -> Bool)!

    override func setUp() {
        super.setUp()
        savedWriter = KeychainSecret.writer
    }

    override func tearDown() {
        KeychainSecret.writer = savedWriter
        KeychainSecret.set("", account: account)
        UserDefaults.standard.removeObject(forKey: account)
        super.tearDown()
    }

    func testFailedKeychainWriteKeepsLegacyValue() {
        KeychainSecret.writer = { _, _ in false }
        let suiteName = "ww-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("sk-legacy", forKey: account)

        XCTAssertEqual(KeychainSecret.loadMigrating(account: account, defaults: defaults), "sk-legacy")
        XCTAssertEqual(defaults.string(forKey: account), "sk-legacy")
    }

    func testMigratesLegacyDefaultsValueAndDeletesIt() {
        UserDefaults.standard.set("sk-legacy", forKey: account)
        XCTAssertEqual(KeychainSecret.loadMigrating(account: account), "sk-legacy")
        XCTAssertNil(UserDefaults.standard.string(forKey: account))
        XCTAssertEqual(KeychainSecret.get(account: account), "sk-legacy")
    }

    func testEmptyValueDeletes() {
        KeychainSecret.set("x", account: account)
        KeychainSecret.set("", account: account)
        XCTAssertNil(KeychainSecret.get(account: account))
    }
}
