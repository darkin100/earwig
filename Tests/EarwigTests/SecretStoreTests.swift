import XCTest
@testable import Earwig

final class SecretStoreTests: XCTestCase {
    private let testKey = "test-\(UUID().uuidString)"

    override func tearDown() {
        super.tearDown()
        SecretStore.delete(testKey)
    }

    func testRoundTrip() {
        XCTAssertNil(SecretStore.get(testKey))
        SecretStore.set("sk-ant-1", for: testKey)
        XCTAssertEqual(SecretStore.get(testKey), "sk-ant-1")
        SecretStore.set("second", for: testKey)
        XCTAssertEqual(SecretStore.get(testKey), "second")
        SecretStore.set("", for: testKey)   // empty deletes
        XCTAssertNil(SecretStore.get(testKey))
    }

    func testAnthropicKeyConvenience() {
        let backup = SecretStore.anthropicKey   // don't clobber a real stored key
        defer { SecretStore.anthropicKey = backup }

        SecretStore.anthropicKey = nil
        XCTAssertNil(SecretStore.anthropicKey)
        SecretStore.anthropicKey = "sk-ant-abc"
        XCTAssertEqual(SecretStore.anthropicKey, "sk-ant-abc")
        SecretStore.anthropicKey = ""
        XCTAssertNil(SecretStore.anthropicKey)
    }
}
