import XCTest
@testable import SocialExportCore

final class TargetSizeTests: XCTestCase {
    func testWidthRuleLandscape() {
        XCTAssertEqual(TargetSize.compute(input: PixelSize(width: 4000, height: 3000), rule: .width(1080)),
                       PixelSize(width: 1080, height: 810))
    }

    func testWidthRulePortrait() {
        XCTAssertEqual(TargetSize.compute(input: PixelSize(width: 3000, height: 4000), rule: .width(1080)),
                       PixelSize(width: 1080, height: 1440))
    }

    func testWidthRuleSquare() {
        XCTAssertEqual(TargetSize.compute(input: PixelSize(width: 2000, height: 2000), rule: .width(1080)),
                       PixelSize(width: 1080, height: 1080))
    }

    func testLongEdgeLandscape() {
        XCTAssertEqual(TargetSize.compute(input: PixelSize(width: 6000, height: 4000), rule: .longEdge(2048)),
                       PixelSize(width: 2048, height: 1365))
    }

    func testLongEdgePortrait() {
        XCTAssertEqual(TargetSize.compute(input: PixelSize(width: 4000, height: 6000), rule: .longEdge(2048)),
                       PixelSize(width: 1365, height: 2048))
    }

    func testNoUpscaleWidth() {
        XCTAssertEqual(TargetSize.compute(input: PixelSize(width: 800, height: 600), rule: .width(1080)),
                       PixelSize(width: 800, height: 600))
    }

    func testNoUpscaleLongEdge() {
        XCTAssertEqual(TargetSize.compute(input: PixelSize(width: 1000, height: 1500), rule: .longEdge(2048)),
                       PixelSize(width: 1000, height: 1500))
    }

    func testExtremeAspectNeverZero() {
        XCTAssertEqual(TargetSize.compute(input: PixelSize(width: 10000, height: 3), rule: .width(1080)),
                       PixelSize(width: 1080, height: 1))
    }
}
