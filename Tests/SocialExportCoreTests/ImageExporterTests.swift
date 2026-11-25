import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import SocialExportCore

final class ImageExporterTests: XCTestCase {
    private var dir: URL!
    private let exporter = ImageExporter(quality: 0.85)

    override func setUp() { dir = Fixtures.tempDir() }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func out(_ name: String = "out.jpg") -> URL { dir.appending(path: name) }

    func testResizesToTargetWidth() throws {
        let src = Fixtures.make(width: 4000, height: 3000, in: dir)
        let size = try exporter.export(source: src, to: out(), rule: .width(1080))
        XCTAssertEqual(size, PixelSize(width: 1080, height: 810))
        XCTAssertTrue(Fixtures.pixelSize(out()) == (1080, 810))
    }

    func testLongEdgePortrait() throws {
        let src = Fixtures.make(width: 3000, height: 4500, in: dir)
        let size = try exporter.export(source: src, to: out(), rule: .longEdge(2048))
        XCTAssertEqual(size, PixelSize(width: 1365, height: 2048))
        XCTAssertTrue(Fixtures.pixelSize(out()) == (1365, 2048))
    }

    func testConvertsP3ToSRGB() throws {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let src = Fixtures.make(width: 1200, height: 800, colorSpace: p3, in: dir)
        XCTAssertEqual(Fixtures.props(src)[kCGImagePropertyProfileName] as? String, "Display P3")
        _ = try exporter.export(source: src, to: out(), rule: .width(1080))
        XCTAssertEqual(Fixtures.props(out())[kCGImagePropertyProfileName] as? String, "sRGB IEC61966-2.1")
    }

    func testBakesOrientation() throws {
        let src = Fixtures.make(width: 3000, height: 2000, orientation: 6, in: dir)
        let size = try exporter.export(source: src, to: out(), rule: .width(1080))
        XCTAssertEqual(size, PixelSize(width: 1080, height: 1620))
        XCTAssertTrue(Fixtures.pixelSize(out()) == (1080, 1620))
        let orientation = Fixtures.props(out())[kCGImagePropertyOrientation] as? Int
        XCTAssertTrue(orientation == nil || orientation == 1, "orientation tag left in output: \(String(describing: orientation))")
    }

    func testStripsMetadata() throws {
        let src = Fixtures.make(width: 1200, height: 800, in: dir)
        XCTAssertNotNil(Fixtures.props(src)[kCGImagePropertyGPSDictionary])
        _ = try exporter.export(source: src, to: out(), rule: .width(1080))
        let p = Fixtures.props(out())
        XCTAssertNil(p[kCGImagePropertyGPSDictionary])
        // ImageIO's JPEG writer always emits a minimal EXIF block (color space, pixel dims); nothing
        // identifying may survive in it or in the TIFF block.
        let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        for key in [kCGImagePropertyExifDateTimeOriginal, kCGImagePropertyExifLensModel, kCGImagePropertyExifUserComment] {
            XCTAssertNil(exif[key], "\(key) survived")
        }
        for key in [kCGImagePropertyTIFFMake, kCGImagePropertyTIFFModel, kCGImagePropertyTIFFSoftware, kCGImagePropertyTIFFDateTime] {
            XCTAssertNil(tiff[key], "\(key) survived")
        }
        XCTAssertEqual(Set(exif.keys.map { $0 as String }).subtracting(["ColorSpace", "PixelXDimension", "PixelYDimension"]), [])
    }

    func testQualityAffectsSize() throws {
        let src = Fixtures.make(width: 2000, height: 1500, in: dir)
        _ = try ImageExporter(quality: 1.0).export(source: src, to: out("q100.jpg"), rule: .width(1080))
        _ = try ImageExporter(quality: 0.85).export(source: src, to: out("q85.jpg"), rule: .width(1080))
        _ = try ImageExporter(quality: 0.3).export(source: src, to: out("q30.jpg"), rule: .width(1080))
        XCTAssertGreaterThan(Fixtures.fileSize(out("q100.jpg")), Fixtures.fileSize(out("q85.jpg")))
        XCTAssertGreaterThan(Fixtures.fileSize(out("q85.jpg")), Fixtures.fileSize(out("q30.jpg")))
    }

    func testHEICInputDecodes() throws {
        guard CGImageDestinationCreateWithURL(dir.appending(path: "probe.heic") as CFURL, UTType.heic.identifier as CFString, 1, nil) != nil else {
            throw XCTSkip("HEIC encoding unavailable on this machine")
        }
        let src = Fixtures.make(width: 1600, height: 1200, type: .heic, in: dir)
        let size = try exporter.export(source: src, to: out(), rule: .width(1080))
        XCTAssertEqual(size, PixelSize(width: 1080, height: 810))
    }

    func testUnreadableThrows() throws {
        let src = dir.appending(path: "notes.txt")
        try Data("hello".utf8).write(to: src)
        XCTAssertThrowsError(try exporter.export(source: src, to: out(), rule: .width(1080))) { error in
            XCTAssertEqual(error as? ExportError, .unreadable(src))
        }
    }

    func testOverwritesExisting() throws {
        let src = Fixtures.make(width: 1200, height: 800, in: dir)
        _ = try exporter.export(source: src, to: out(), rule: .width(1080))
        let first = try FileManager.default.attributesOfItem(atPath: out().path)[.modificationDate] as! Date
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertNoThrow(try exporter.export(source: src, to: out(), rule: .width(600)))
        let second = try FileManager.default.attributesOfItem(atPath: out().path)[.modificationDate] as! Date
        XCTAssertGreaterThan(second, first)
        XCTAssertTrue(Fixtures.pixelSize(out()) == (600, 400))
    }

    func testPerf50MP() throws {
        guard ProcessInfo.processInfo.environment["SOCIAL_EXPORT_PERF"] == "1" else {
            throw XCTSkip("set SOCIAL_EXPORT_PERF=1 to run")
        }
        let src = Fixtures.make(width: 8660, height: 5774, in: dir)
        let start = Date()
        _ = try exporter.export(source: src, to: out("a.jpg"), rule: .width(1080))
        _ = try exporter.export(source: src, to: out("b.jpg"), rule: .width(1080))
        _ = try exporter.export(source: src, to: out("c.jpg"), rule: .longEdge(2048))
        let elapsed = Date().timeIntervalSince(start)
        print("perf50MP: \(elapsed)s")
        XCTAssertLessThan(elapsed, 3)
    }
}
