import XCTest
@testable import SocialExportCore

final class ExportSpecTests: XCTestCase {
    func testDefaultsAreThreePlatforms() {
        let specs = ExportSpec.defaults
        XCTAssertEqual(specs.map(\.id), ["instagram", "threads", "facebook"])
        XCTAssertEqual(specs.map(\.folder), ["instagram", "threads", "facebook"])
        XCTAssertEqual(specs.map(\.rule), [.width(1080), .width(1080), .longEdge(2048)])
        XCTAssertEqual(specs.map(\.quality), [0.85, 0.85, 0.95])
        XCTAssertEqual(specs.map(\.format), [.jpeg, .jpeg, .jpeg])
    }

    /// Exactly what 1.0.x stored in the app-group defaults (no `format` key).
    static let legacyJSON = #"[{"folder":"instagram","rule":{"width":{"_0":1080}},"quality":0.85,"id":"instagram"},{"folder":"threads","rule":{"width":{"_0":1080}},"quality":0.8,"id":"threads"},{"folder":"facebook","rule":{"longEdge":{"_0":2048}},"quality":0.85,"id":"facebook"}]"#

    func testLegacyJSONWithoutFormatDecodesAsJPEG() throws {
        let specs = try JSONDecoder().decode([ExportSpec].self, from: Data(Self.legacyJSON.utf8))
        XCTAssertEqual(specs.map(\.id), ["instagram", "threads", "facebook"])
        XCTAssertEqual(specs.map(\.rule), [.width(1080), .width(1080), .longEdge(2048)])
        XCTAssertEqual(specs.map(\.quality), [0.85, 0.8, 0.85])
        XCTAssertEqual(specs.map(\.format), [.jpeg, .jpeg, .jpeg])
    }

    func testTIFFFormatRoundTripsJSON() throws {
        var specs = ExportSpec.defaults
        specs[2].format = .tiff8
        let data = try JSONEncoder().encode(specs)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""format":"tiff8""#))
        XCTAssertEqual(try JSONDecoder().decode([ExportSpec].self, from: data), specs)
    }

    func testFileExtensions() {
        XCTAssertEqual(OutputFormat.jpeg.fileExtension, "jpg")
        XCTAssertEqual(OutputFormat.tiff8.fileExtension, "tif")
    }

    func testSpecRoundTripsJSON() throws {
        let data = try JSONEncoder().encode(ExportSpec.defaults)
        let decoded = try JSONDecoder().decode([ExportSpec].self, from: data)
        XCTAssertEqual(decoded, ExportSpec.defaults)
    }
}
