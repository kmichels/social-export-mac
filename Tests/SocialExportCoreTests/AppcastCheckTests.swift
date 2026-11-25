import XCTest
@testable import SocialExportCore

final class AppcastCheckTests: XCTestCase {
    /// Three items in the order 3, 5, 4: build 3 and 4 on the <sparkle:version> element, 5 on the enclosure attribute.
    static let fixture = Data("""
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <title>Social Export</title>
        <item>
          <title>1.0</title>
          <sparkle:version>3</sparkle:version>
          <sparkle:shortVersionString>1.0</sparkle:shortVersionString>
          <enclosure url="https://apps.tonalphoto.com/social-export/releases/SocialExport-1.0.dmg" length="1" type="application/octet-stream"/>
        </item>
        <item>
          <title>1.1</title>
          <enclosure url="https://apps.tonalphoto.com/social-export/releases/SocialExport-1.1.dmg" sparkle:version="5" sparkle:shortVersionString="1.1" length="1" type="application/octet-stream"/>
        </item>
        <item>
          <title>1.0.1</title>
          <sparkle:version>4</sparkle:version>
          <enclosure url="https://apps.tonalphoto.com/social-export/releases/SocialExport-1.0.1.dmg" length="1" type="application/octet-stream"/>
        </item>
      </channel>
    </rss>
    """.utf8)

    func testLatestBuildPicksNumericMax() {
        XCTAssertEqual(AppcastCheck.latestBuild(in: Self.fixture), 5)
    }

    func testLatestBuildIgnoresNonNumeric() {
        let data = Data(String(decoding: Self.fixture, as: UTF8.self)
            .replacingOccurrences(of: "<sparkle:version>4</sparkle:version>", with: "<sparkle:version>1.0.1</sparkle:version>").utf8)
        XCTAssertEqual(AppcastCheck.latestBuild(in: data), 5)
    }

    func testMalformedXMLIsNil() {
        XCTAssertNil(AppcastCheck.latestBuild(in: Data("<rss><channel><item>".utf8)))
    }

    func testNoVersionIsNil() {
        let data = Data("<rss xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\"><channel><item><title>x</title></item></channel></rss>".utf8)
        XCTAssertNil(AppcastCheck.latestBuild(in: data))
    }

    func testShouldCheckWhenNeverChecked() {
        XCTAssertTrue(AppcastCheck.shouldCheck(now: Date(), lastCheck: nil))
    }

    func testShouldCheckWithin24hFalse() {
        let now = Date()
        XCTAssertFalse(AppcastCheck.shouldCheck(now: now, lastCheck: now.addingTimeInterval(-3600)))
    }

    func testShouldCheckAfter24hTrue() {
        let now = Date()
        XCTAssertTrue(AppcastCheck.shouldCheck(now: now, lastCheck: now.addingTimeInterval(-90_000)))
    }

    func testNudgeNilWhenCurrent() {
        XCTAssertNil(AppcastCheck.nudgeText(current: 5, latest: 5))
        XCTAssertNil(AppcastCheck.nudgeText(current: 5, latest: nil))
        XCTAssertNil(AppcastCheck.nudgeText(current: 6, latest: 5))
    }

    func testNudgeWhenNewer() {
        XCTAssertEqual(AppcastCheck.nudgeText(current: 5, latest: 6), " · Update available: open Social Export")
    }

    func testConstants() {
        XCTAssertEqual(AppcastCheck.feedURL.absoluteString, "https://apps.tonalphoto.com/social-export/appcast.xml")
        XCTAssertEqual(AppcastCheck.interval, 86_400)
    }
}
