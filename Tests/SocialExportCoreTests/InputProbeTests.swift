import UniformTypeIdentifiers
import XCTest
@testable import SocialExportCore

final class InputProbeTests: XCTestCase {
    private var dir: URL!

    override func setUp() { dir = Fixtures.tempDir() }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    // IJG (libjpeg) luma tables in zigzag order, computed independently from Annex K with IJG quality scaling.
    private let ijg50: [UInt8] = [16, 11, 12, 14, 12, 10, 16, 14, 13, 14, 18, 17, 16, 19, 24, 40, 26, 24, 22, 22, 24, 49, 35, 37, 29, 40, 58, 51, 61, 60, 57, 51, 56, 55, 64, 72, 92, 78, 64, 68, 87, 69, 55, 56, 80, 109, 81, 87, 95, 98, 103, 104, 103, 62, 77, 113, 121, 112, 100, 120, 92, 101, 103, 99]
    private let ijg90: [UInt8] = [3, 2, 2, 3, 2, 2, 3, 3, 3, 3, 4, 3, 3, 4, 5, 8, 5, 5, 4, 4, 5, 10, 7, 7, 6, 8, 12, 10, 12, 12, 11, 10, 11, 11, 13, 14, 18, 16, 13, 14, 17, 14, 11, 11, 16, 22, 16, 17, 19, 20, 21, 21, 21, 12, 15, 23, 24, 22, 20, 24, 18, 20, 21, 20]

    /// SOI, an APP0 to skip, one DQT (table 0), a baseline SOF0 with three components, EOI.
    private func jpegBytes(luma: [UInt8], ySampling: UInt8) -> Data {
        var d: [UInt8] = [0xFF, 0xD8]
        d += [0xFF, 0xE0, 0x00, 0x06, 0x4A, 0x46, 0x49, 0x46]          // APP0, length 6
        d += [0xFF, 0xDB, 0x00, 0x43, 0x00] + luma                    // DQT, Pq=0 Tq=0
        d += [0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00, 0x10, 0x00, 0x20, 0x03,
              0x01, ySampling, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01] // SOF0 16x32, Y uses table 0
        d += [0xFF, 0xD9]
        return Data(d)
    }

    func testIJG50With420() throws {
        let s = try XCTUnwrap(InputProbe.jpegSummary(jpegBytes(luma: ijg50, ySampling: 0x22)))
        XCTAssertEqual(s, JPEGSummary(subsampling: "4:2:0", lumaQ0: 16, lumaP50: 56, lumaMax: 121, nearestIJG: 50))
    }

    func testIJG90With444() throws {
        let s = try XCTUnwrap(InputProbe.jpegSummary(jpegBytes(luma: ijg90, ySampling: 0x11)))
        XCTAssertEqual(s, JPEGSummary(subsampling: "4:4:4", lumaQ0: 3, lumaP50: 11, lumaMax: 24, nearestIJG: 90))
    }

    func testSubsampling422() throws {
        XCTAssertEqual(InputProbe.jpegSummary(jpegBytes(luma: ijg90, ySampling: 0x21))?.subsampling, "4:2:2")
    }

    func testNotAJPEGHasNoSummary() {
        XCTAssertNil(InputProbe.jpegSummary(Data("hello".utf8)))
        XCTAssertNil(InputProbe.jpegSummary(Data([0xFF, 0xD8, 0xFF, 0xD9])))
    }

    func testDescribeImageIOJPEG() {
        let src = Fixtures.make(width: 1600, height: 1200, in: dir)
        let line = InputProbe.describe(src)
        XCTAssertTrue(line.hasPrefix("fixture.jpeg public.jpeg 1600x1200 \(Fixtures.fileSize(src))B jpeg("), line)
        XCTAssertTrue(line.contains("ijg~"), line)
    }

    func testDescribeTIFF() {
        let src = Fixtures.make(width: 1600, height: 1200, type: .tiff, in: dir)
        let line = InputProbe.describe(src)
        XCTAssertTrue(line.hasPrefix("fixture.tiff public.tiff 1600x1200 "), line)
        XCTAssertFalse(line.contains("jpeg("), line)
    }

    func testDescribeUnreadable() throws {
        let src = dir.appending(path: "notes.txt")
        try Data("hello".utf8).write(to: src)
        XCTAssertEqual(InputProbe.describe(src), "notes.txt unreadable 5B")
    }
}
