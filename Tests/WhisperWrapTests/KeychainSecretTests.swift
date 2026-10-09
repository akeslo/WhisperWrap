import XCTest
@testable import WhisperWrap

@MainActor
final class KeychainSecretTests: XCTestCase {
    private let account = "test-\(UUID().uuidString)"

    override func tearDown() {
        KeychainSecret.set("", account: account)
        UserDefaults.standard.removeObject(forKey: account)
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
