import XCTest
@testable import SocialExportCore

final class ExportRunTests: XCTestCase {
    private var dir: URL!
    private var root: URL!
    private let specs = ExportSpec.defaults

    override func setUp() {
        dir = Fixtures.tempDir()
        root = dir.appending(path: "Socials")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func exists(_ spec: ExportSpec, _ name: String) -> Bool {
        FileManager.default.fileExists(atPath: OutputPath.url(root: root, spec: spec, inputFilename: name).path)
    }

    func testTwoInputsThreeSpecsWritesSix() async {
        let a = Fixtures.make(width: 1600, height: 1200, name: "a", in: dir)
        let b = Fixtures.make(width: 1200, height: 1600, name: "b", in: dir)
        let result = await ExportRun.run(inputs: [a, b], specs: specs, root: root)
        XCTAssertEqual(result.written.count, 6)
        XCTAssertTrue(result.failures.isEmpty)
        for spec in specs {
            XCTAssertTrue(exists(spec, "a.jpeg"), "\(spec.id)/a.jpg missing")
            XCTAssertTrue(exists(spec, "b.jpeg"), "\(spec.id)/b.jpg missing")
        }
        XCTAssertEqual(result.notificationText, "Exported 2 photos to Socials")
    }

    func testMixedFormatsWriteJpgAndTif() async {
        let a = Fixtures.make(width: 1600, height: 1200, name: "a", in: dir)
        var mixed = specs
        mixed[2].format = .tiff8
        let result = await ExportRun.run(inputs: [a], specs: mixed, root: root)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(result.written.map(\.lastPathComponent), ["a.jpg", "a.jpg", "a.tif"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "facebook/a.tif").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "facebook/a.jpg").path))
    }

    func testOneInputSingular() async {
        let a = Fixtures.make(width: 1600, height: 1200, name: "a", in: dir)
        let result = await ExportRun.run(inputs: [a], specs: specs, root: root)
        XCTAssertEqual(result.notificationText, "Exported 1 photo to Socials")
    }

    func testBadInputContinues() async throws {
        let good = Fixtures.make(width: 1600, height: 1200, name: "good", in: dir)
        let bad = dir.appending(path: "bad.txt")
        try Data("x".utf8).write(to: bad)
        let result = await ExportRun.run(inputs: [good, bad], specs: specs, root: root)
        XCTAssertEqual(result.written.count, 3)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.failures.first?.input, bad)
        XCTAssertEqual(result.failures.first?.error, .unreadable(bad))
        XCTAssertTrue(result.notificationText.hasPrefix("Social Export failed on bad.txt: "), result.notificationText)
        XCTAssertTrue(result.notificationText.hasSuffix(" (1 exported)"), result.notificationText)
    }

    func testDuplicateNamesOverwrite() async {
        let d1 = dir.appending(path: "one"), d2 = dir.appending(path: "two")
        try! FileManager.default.createDirectory(at: d1, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: d2, withIntermediateDirectories: true)
        let a = Fixtures.make(width: 1600, height: 1200, name: "IMG_0001", in: d1)
        let b = Fixtures.make(width: 2000, height: 1000, name: "IMG_0001", in: d2)
        let result = await ExportRun.run(inputs: [a, b], specs: specs, root: root)
        // Same output name: both are exported in order, the second overwrites, so 6 writes land on 3 files.
        XCTAssertEqual(result.written.count, 6)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(result.notificationText, "Exported 2 photos to Socials")
        let files = try! FileManager.default.contentsOfDirectory(atPath: root.appending(path: "instagram").path)
        XCTAssertEqual(files, ["IMG_0001.jpg"])
        XCTAssertTrue(Fixtures.pixelSize(root.appending(path: "instagram/IMG_0001.jpg")) == (1080, 540), "second input should win")
    }

    func testSkippedCountInText() async {
        let a = Fixtures.make(width: 1600, height: 1200, name: "a", in: dir)
        let result = await ExportRun.run(inputs: [a], specs: specs, root: root, skipped: 1)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertEqual(result.notificationText, "Exported 1 photo to Socials, 1 items skipped")
    }

    func testRootIsFile() async throws {
        try Data("x".utf8).write(to: root)
        let a = Fixtures.make(width: 1600, height: 1200, name: "a", in: dir)
        let result = await ExportRun.run(inputs: [a], specs: specs, root: root)
        XCTAssertTrue(result.written.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
        guard case .write? = result.failures.first?.error else { return XCTFail("expected .write, got \(String(describing: result.failures.first?.error))") }
        XCTAssertTrue(result.notificationText.hasPrefix("Social Export failed on a.jpeg: "))
        XCTAssertFalse(result.notificationText.contains("exported)"))
    }

    func testOrderIsDeterministicWithManyInputs() async {
        let inputs = (0..<8).map { Fixtures.make(width: 800, height: 600, name: "p\($0)", in: dir) }
        let result = await ExportRun.run(inputs: inputs, specs: specs, root: root)
        XCTAssertEqual(result.written.count, 24)
        XCTAssertEqual(result.written.prefix(3).map(\.lastPathComponent), ["p0.jpg", "p0.jpg", "p0.jpg"])
        XCTAssertEqual(result.written.suffix(3).map { $0.deletingLastPathComponent().lastPathComponent }, ["instagram", "threads", "facebook"])
    }
}

extension ExportRunTests {
    /// Same output name, later input unreadable: the earlier input's files must stay on disk and the
    /// notification must not count the failed one as exported.
    func testLaterSameNameInputFailingKeepsEarlierFiles() async throws {
        let good = Fixtures.make(width: 1600, height: 1200, name: "X", in: dir)
        let bad = dir.appending(path: "X.png")
        try Data("not an image".utf8).write(to: bad)
        let result = await ExportRun.run(inputs: [good, bad], specs: specs, root: root)
        XCTAssertEqual(result.written.count, 3)
        XCTAssertEqual(result.failures.map(\.input), [bad])
        XCTAssertTrue(exists(specs[0], "X.jpeg"), "good input's file should be on disk")
        XCTAssertTrue(Fixtures.pixelSize(root.appending(path: "instagram/X.jpg")) == (1080, 810))
        XCTAssertEqual(result.notificationText, "Social Export failed on X.png: not a readable image (1 exported)")
    }

    /// ~/Pictures is case-insensitive APFS: IMG_0001.JPG and img_0001.jpeg are the same output file and must
    /// be written in order, never concurrently. Last input wins.
    func testCaseInsensitiveNameCollisionIsSequential() async {
        let d1 = dir.appending(path: "one"), d2 = dir.appending(path: "two")
        try! FileManager.default.createDirectory(at: d1, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: d2, withIntermediateDirectories: true)
        let a = Fixtures.make(width: 1600, height: 1200, name: "IMG_0001", in: d1)
        let b = Fixtures.make(width: 2000, height: 1000, name: "img_0001", in: d2)
        for _ in 0..<5 {
            let result = await ExportRun.run(inputs: [a, b], specs: specs, root: root)
            XCTAssertTrue(result.failures.isEmpty)
            XCTAssertEqual(result.notificationText, "Exported 2 photos to Socials")
            let files = try! FileManager.default.contentsOfDirectory(atPath: root.appending(path: "instagram").path)
            XCTAssertEqual(files.count, 1)
            XCTAssertTrue(Fixtures.pixelSize(root.appending(path: "instagram/\(files[0])")) == (1080, 540), "last input should win")
        }
    }
}

extension ExportRunTests {
    /// A cancelled task must not start exporting; what was already written stays, nothing new is attempted.
    func testCancelledTaskStartsNoWork() async {
        let inputs = (0..<4).map { Fixtures.make(width: 800, height: 600, name: "c\($0)", in: dir) }
        let specs = self.specs, root = self.root!
        let task = Task { () -> ExportResult in
            try? await Task.sleep(for: .seconds(5))   // returns immediately once cancelled
            return await ExportRun.run(inputs: inputs, specs: specs, root: root)
        }
        task.cancel()
        let result = await task.value
        XCTAssertEqual(result.written, [])
        XCTAssertEqual(result.failures.count, inputs.count)
        XCTAssertTrue(result.notificationText.hasPrefix("Social Export failed on c0.jpeg: cancelled"), result.notificationText)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
}
