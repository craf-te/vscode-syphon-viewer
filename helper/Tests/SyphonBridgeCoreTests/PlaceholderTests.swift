import XCTest
@testable import SyphonBridgeCore

// Keeps the test target non-empty and covers ServerInfo's synthesised Equatable.
final class PlaceholderTests: XCTestCase {
    func testServerInfoIsEquatable() {
        let a = ServerInfo(uuid: "u", name: "n", appName: "a")
        XCTAssertEqual(a, ServerInfo(uuid: "u", name: "n", appName: "a"))
    }
}
