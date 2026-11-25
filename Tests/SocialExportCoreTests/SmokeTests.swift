import XCTest
@testable import SocialExportCore

final class SmokeTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(SocialExportCore.version, "0.1.0")
    }
}
