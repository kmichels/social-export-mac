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

    // MARK: 8-bit TIFF

    private let tiffExporter = ImageExporter(quality: 0.85, format: .tiff8)

    func testTIFFIsEightBitRGBUncompressedNoAlpha() throws {
        let src = Fixtures.make(width: 4000, height: 3000, in: dir)
        let size = try tiffExporter.export(source: src, to: out("out.tif"), rule: .width(1080))
        XCTAssertEqual(size, PixelSize(width: 1080, height: 810))
        let tags = Fixtures.tiffTags(out("out.tif"))
        XCTAssertEqual(tags[256], [1080], "ImageWidth")
        XCTAssertEqual(tags[257], [810], "ImageLength")
        XCTAssertEqual(tags[258], [8, 8, 8], "BitsPerSample")
        XCTAssertEqual(tags[277], [3], "SamplesPerPixel")
        XCTAssertNil(tags[338], "ExtraSamples present: output has an alpha or extra channel")
        XCTAssertEqual(tags[259], [1], "Compression must be none")
        XCTAssertEqual(tags[262], [2], "PhotometricInterpretation RGB")
        XCTAssertNotNil(tags[34675], "ICC profile missing")
        let p = Fixtures.props(out("out.tif"))
        XCTAssertEqual(p[kCGImagePropertyDepth] as? Int, 8)
        XCTAssertNotEqual(p[kCGImagePropertyHasAlpha] as? Bool, true)
        XCTAssertEqual(p[kCGImagePropertyProfileName] as? String, "sRGB IEC61966-2.1")
    }

    func testTIFFConvertsP3ToSRGB() throws {
        let src = Fixtures.make(width: 1200, height: 800, colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!, in: dir)
        _ = try tiffExporter.export(source: src, to: out("p3.tif"), rule: .width(1080))
        XCTAssertEqual(Fixtures.props(out("p3.tif"))[kCGImagePropertyProfileName] as? String, "sRGB IEC61966-2.1")
    }

    func testTIFFBakesOrientationAndLongEdge() throws {
        let src = Fixtures.make(width: 3000, height: 2000, orientation: 6, in: dir)
        let size = try tiffExporter.export(source: src, to: out("rot.tif"), rule: .longEdge(2048))
        XCTAssertEqual(size, PixelSize(width: 1365, height: 2048))
        XCTAssertTrue(Fixtures.pixelSize(out("rot.tif")) == (1365, 2048))
        let orientation = Fixtures.props(out("rot.tif"))[kCGImagePropertyOrientation] as? Int
        XCTAssertTrue(orientation == nil || orientation == 1, "orientation tag left in output: \(String(describing: orientation))")
    }

    func testTIFFStripsMetadata() throws {
        let src = Fixtures.make(width: 1200, height: 800, in: dir)
        _ = try tiffExporter.export(source: src, to: out("meta.tif"), rule: .width(1080))
        let p = Fixtures.props(out("meta.tif"))
        XCTAssertNil(p[kCGImagePropertyGPSDictionary])
        XCTAssertNil(p[kCGImagePropertyExifDictionary])
        let tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        for key in [kCGImagePropertyTIFFMake, kCGImagePropertyTIFFModel, kCGImagePropertyTIFFSoftware, kCGImagePropertyTIFFDateTime] {
            XCTAssertNil(tiff[key], "\(key) survived")
        }
        let tags = Fixtures.tiffTags(out("meta.tif"))
        for tag: UInt16 in [271, 272, 305, 306, 34665, 34853] { // Make, Model, Software, DateTime, ExifIFD, GPSIFD
            XCTAssertNil(tags[tag], "TIFF tag \(tag) present")
        }
    }

    func testTIFFIgnoresQuality() throws {
        let src = Fixtures.make(width: 2000, height: 1500, in: dir)
        _ = try ImageExporter(quality: 0.3, format: .tiff8).export(source: src, to: out("q30.tif"), rule: .width(1080))
        _ = try ImageExporter(quality: 1.0, format: .tiff8).export(source: src, to: out("q100.tif"), rule: .width(1080))
        XCTAssertEqual(try Data(contentsOf: out("q30.tif")), try Data(contentsOf: out("q100.tif")))
        // Uncompressed: at least the raw pixel payload.
        XCTAssertGreaterThanOrEqual(Fixtures.fileSize(out("q30.tif")), 1080 * 810 * 3)
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
