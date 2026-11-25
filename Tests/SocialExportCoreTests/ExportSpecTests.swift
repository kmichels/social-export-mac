import XCTest
@testable import SocialExportCore

final class ExportSpecTests: XCTestCase {
    func testDefaultsAreThreePlatforms() {
        let specs = ExportSpec.defaults
        XCTAssertEqual(specs.map(\.id), ["instagram", "threads", "facebook"])
        XCTAssertEqual(specs.map(\.folder), ["instagram", "threads", "facebook"])
        XCTAssertEqual(specs.map(\.rule), [.width(1080), .width(1080), .longEdge(2048)])
        XCTAssertEqual(specs.map(\.quality), [0.85, 0.85, 0.85])
    }

    func testSpecRoundTripsJSON() throws {
        let data = try JSONEncoder().encode(ExportSpec.defaults)
        let decoded = try JSONDecoder().decode([ExportSpec].self, from: data)
        XCTAssertEqual(decoded, ExportSpec.defaults)
    }
}
