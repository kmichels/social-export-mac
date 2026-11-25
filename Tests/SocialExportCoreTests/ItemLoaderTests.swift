import UniformTypeIdentifiers
import XCTest
@testable import SocialExportCore

final class ItemLoaderTests: XCTestCase {
    private var dir: URL!
    private var out: URL!

    override func setUp() {
        dir = Fixtures.tempDir()
        out = dir.appending(path: "loaded")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func relative(_ files: [URL]) -> [String] {
        files.map { $0.path.replacingOccurrences(of: out.path + "/", with: "") }
    }

    /// Photos' providers carry the original name in `suggestedName`; `contentsOf:` providers in tests do not,
    /// so set it the way a share sheet does.
    private func provider(for url: URL) -> NSItemProvider {
        let p = NSItemProvider(contentsOf: url)!
        p.suggestedName = url.lastPathComponent
        return p
    }

    func testLoadsImageProvider() async throws {
        let fixture = Fixtures.make(width: 400, height: 300, name: "photo", in: dir)
        let result = await ItemLoader.load([provider(for: fixture)], into: out)
        XCTAssertEqual(relative(result.files), ["item_0/photo.jpeg"])
        XCTAssertEqual(result.skipped, 0)
        XCTAssertEqual(try Data(contentsOf: result.files[0]), try Data(contentsOf: fixture))
    }

    func testSkipsNonImage() async throws {
        let text = dir.appending(path: "notes.txt")
        try Data("hello".utf8).write(to: text)
        let result = await ItemLoader.load([NSItemProvider(contentsOf: text)!], into: out)
        XCTAssertEqual(result.files, [])
        XCTAssertEqual(result.skipped, 1)
    }

    func testClashKeepsBothNames() async {
        let d1 = dir.appending(path: "one"), d2 = dir.appending(path: "two")
        try! FileManager.default.createDirectory(at: d1, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: d2, withIntermediateDirectories: true)
        let a = Fixtures.make(width: 400, height: 300, name: "a", in: d1)
        let b = Fixtures.make(width: 300, height: 400, name: "a", in: d2)
        let result = await ItemLoader.load([provider(for: a), provider(for: b)], into: out)
        XCTAssertEqual(relative(result.files), ["item_0/a.jpeg", "item_1/a.jpeg"])
    }

    func testFallsBackToTempNameWithoutSuggestedName() async {
        let fixture = Fixtures.make(width: 400, height: 300, name: "photo", in: dir)
        let result = await ItemLoader.load([NSItemProvider(contentsOf: fixture)!], into: out)
        XCTAssertEqual(result.files.count, 1)
        XCTAssertEqual(result.files[0].pathExtension, "jpeg")
    }

    func testFilenameAddsExtensionWhenSuggestedNameLacksOne() {
        let name = ItemLoader.filename(preferredName: "IMG_0001", type: UTType.jpeg.identifier, tempURL: URL(fileURLWithPath: "/tmp/JPEG image.jpeg"))
        XCTAssertEqual(name, "IMG_0001.jpeg")
    }

    func testPicksConcreteImageType() async throws {
        let fixture = Fixtures.make(width: 400, height: 300, name: "only-jpeg", in: dir)
        let provider = NSItemProvider()
        provider.suggestedName = "only-jpeg.jpeg"
        provider.registerFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier, fileOptions: [], visibility: .all) { completion in
            completion(fixture, false, nil)
            return nil
        }
        XCTAssertEqual(provider.registeredTypeIdentifiers, [UTType.jpeg.identifier])
        let result = await ItemLoader.load([provider], into: out)
        XCTAssertEqual(result.files.count, 1)
        XCTAssertEqual(result.skipped, 0)
        XCTAssertEqual(try Data(contentsOf: result.files[0]), try Data(contentsOf: fixture))
    }

    func testProviderFailureCountsAsSkipped() async {
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier, fileOptions: [], visibility: .all) { completion in
            completion(nil, false, CocoaError(.fileNoSuchFile))
            return nil
        }
        let result = await ItemLoader.load([provider], into: out)
        XCTAssertEqual(result.files, [])
        XCTAssertEqual(result.skipped, 1)
    }
}

extension ItemLoaderTests {
    /// Photos.app on macOS hands share extensions a `public.file-url` item pointing at a temporary JPEG export,
    /// with no image type registered. That must load as an image, named after the file.
    func testLoadsFileURLOnlyProvider() async throws {
        let fixture = Fixtures.make(width: 400, height: 300, name: "B0038375", in: dir)
        let provider = NSItemProvider(item: fixture as NSURL, typeIdentifier: UTType.fileURL.identifier)
        XCTAssertEqual(provider.registeredTypeIdentifiers, [UTType.fileURL.identifier])
        let result = await ItemLoader.load([provider], into: out)
        XCTAssertEqual(relative(result.files), ["item_0/B0038375.jpeg"])
        XCTAssertEqual(result.skipped, 0)
        let loaded = try XCTUnwrap(result.files.first)
        XCTAssertEqual(try Data(contentsOf: loaded), try Data(contentsOf: fixture))
    }

    func testFileURLToNonImageIsSkipped() async throws {
        let text = dir.appending(path: "notes.txt")
        try Data("hello".utf8).write(to: text)
        let provider = NSItemProvider(item: text as NSURL, typeIdentifier: UTType.fileURL.identifier)
        let result = await ItemLoader.load([provider], into: out)
        XCTAssertEqual(result.files, [])
        XCTAssertEqual(result.skipped, 1)
    }
}

extension ItemLoaderTests {
    /// Photos registers public.jpeg AND public.file-url; on macOS 27 the jpeg file representation fails, so the
    /// loader must fall through to the file URL instead of skipping.
    func testFallsBackToFileURLWhenImageRepresentationFails() async throws {
        let fixture = Fixtures.make(width: 400, height: 300, name: "B0038375", in: dir)
        let provider = NSItemProvider(item: fixture as NSURL, typeIdentifier: UTType.fileURL.identifier)
        provider.registerFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier, fileOptions: [], visibility: .all) { completion in
            completion(nil, false, CocoaError(.fileReadNoPermission))
            return nil
        }
        let result = await ItemLoader.load([provider], into: out)
        XCTAssertEqual(relative(result.files), ["item_0/B0038375.jpeg"])
        XCTAssertEqual(result.skipped, 0)
        XCTAssertTrue(result.notes.contains { $0.contains("public.jpeg") }, "notes should record the failed representation: \(result.notes)")
    }

    func testNotesRecordSkipReason() async throws {
        let text = dir.appending(path: "notes.txt")
        try Data("hello".utf8).write(to: text)
        let result = await ItemLoader.load([NSItemProvider(contentsOf: text)!], into: out)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertEqual(result.notes.count, 1)
    }
}
