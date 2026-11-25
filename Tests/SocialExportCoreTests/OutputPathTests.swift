import XCTest
@testable import SocialExportCore

final class OutputPathTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    func testUrlUsesStemAndJpg() {
        let url = OutputPath.url(root: root, spec: ExportSpec.defaults[0], inputFilename: "IMG_0001.HEIC")
        XCTAssertEqual(url, root.appending(path: "instagram/IMG_0001.jpg"))
    }

    func testUrlKeepsDotsInStem() {
        let url = OutputPath.url(root: root, spec: ExportSpec.defaults[2], inputFilename: "2026.10.29 beach.jpeg")
        XCTAssertEqual(url, root.appending(path: "facebook/2026.10.29 beach.jpg"))
    }

    func testEnsureDirectoryCreatesNested() throws {
        let url = root.appending(path: "threads/x.jpg")
        try OutputPath.ensureDirectory(for: url)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "threads").path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testEnsureDirectoryExistingIsFine() throws {
        let url = root.appending(path: "threads/x.jpg")
        try OutputPath.ensureDirectory(for: url)
        XCTAssertNoThrow(try OutputPath.ensureDirectory(for: url))
    }

    func testEnsureDirectoryFailsWhenRootIsFile() throws {
        try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not a dir".utf8).write(to: root)
        let url = root.appending(path: "threads/x.jpg")
        XCTAssertThrowsError(try OutputPath.ensureDirectory(for: url)) { error in
            guard case .write? = error as? ExportError else {
                return XCTFail("expected ExportError.write, got \(error)")
            }
        }
    }
}
