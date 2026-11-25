import XCTest
@testable import SocialExportCore

final class SpecStoreTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testLoadEmptyReturnsDefaults() {
        XCTAssertEqual(SpecStore(defaults: defaults).load(), ExportSpec.defaults)
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = SpecStore(defaults: defaults)
        var specs = ExportSpec.defaults
        specs[2].quality = 0.9
        try store.save(specs)
        XCTAssertEqual(store.load(), specs)
        XCTAssertEqual(store.load()[2].quality, 0.9)
    }

    func testLegacyStoredSpecsLoadAsStored() {
        defaults.set(Data(ExportSpecTests.legacyJSON.utf8), forKey: "exportSpecs")
        let specs = SpecStore(defaults: defaults).load()
        XCTAssertNotEqual(specs, ExportSpec.defaults, "legacy specs were replaced by defaults")
        XCTAssertEqual(specs.map(\.quality), [0.85, 0.8, 0.85])
        XCTAssertEqual(specs.map(\.format), [.jpeg, .jpeg, .jpeg])
    }

    func testCorruptDataReturnsDefaults() {
        defaults.set(Data("nope".utf8), forKey: "exportSpecs")
        XCTAssertEqual(SpecStore(defaults: defaults).load(), ExportSpec.defaults)
    }

    func testOutputRootEndsWithPicturesSocials() {
        XCTAssertEqual(Array(SpecStore.outputRoot.pathComponents.suffix(2)), ["Pictures", "Socials"])
    }

    func testAppGroupID() {
        XCTAssertEqual(SpecStore.appGroupID, "85QL287QYW.com.tonalphoto.socialexport")
    }
}
