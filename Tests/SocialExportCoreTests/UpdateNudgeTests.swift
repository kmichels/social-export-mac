import Foundation
import XCTest
@testable import SocialExportCore

/// Serves canned responses for the nudge's feed URL. `mode` is global because URLProtocol is class-registered.
final class FeedStub: URLProtocol, @unchecked Sendable {
    enum Mode { case fixture, notFound, hang }
    nonisolated(unsafe) static var mode: Mode = .fixture
    nonisolated(unsafe) static var requests = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests += 1
        switch Self.mode {
        case .fixture:
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/xml"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: AppcastCheckTests.fixture)
            client?.urlProtocolDidFinishLoading(self)
        case .notFound:
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        case .hang:
            break   // never answers; the session timeout ends it
        }
    }

    override func stopLoading() {}
}

final class UpdateNudgeTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "test.nudge.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        FeedStub.mode = .fixture
        FeedStub.requests = 0
    }

    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    private func session(timeout: TimeInterval = 2) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FeedStub.self]
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        return URLSession(configuration: config)
    }

    func testFetchesAndNudgesWhenNewer() async {
        let text = await UpdateNudge(defaults: defaults, currentBuild: 3, session: session()).suffix()
        XCTAssertEqual(text, AppcastCheck.nudge)
        XCTAssertEqual(defaults.integer(forKey: UpdateNudge.latestBuildKey), 5)
        XCTAssertNotNil(defaults.object(forKey: UpdateNudge.lastCheckKey) as? Date)
        XCTAssertEqual(FeedStub.requests, 1)
    }

    func testNoFetchWithinInterval() async {
        defaults.set(Date().addingTimeInterval(-60), forKey: UpdateNudge.lastCheckKey)
        defaults.set(5, forKey: UpdateNudge.latestBuildKey)
        let text = await UpdateNudge(defaults: defaults, currentBuild: 3, session: session()).suffix()
        XCTAssertEqual(text, AppcastCheck.nudge)
        XCTAssertEqual(FeedStub.requests, 0)
    }

    func testNoNudgeWhenCurrent() async {
        let text = await UpdateNudge(defaults: defaults, currentBuild: 5, session: session()).suffix()
        XCTAssertNil(text)
    }

    func testServerErrorIsSilent() async {
        FeedStub.mode = .notFound
        let text = await UpdateNudge(defaults: defaults, currentBuild: 3, session: session()).suffix()
        XCTAssertNil(text)
        XCTAssertNotNil(defaults.object(forKey: UpdateNudge.lastCheckKey) as? Date, "a broken feed must not be hammered")
    }

    func testTimeoutIsSilent() async {
        FeedStub.mode = .hang
        let start = Date()
        let text = await UpdateNudge(defaults: defaults, currentBuild: 3, session: session(timeout: 1)).suffix()
        XCTAssertNil(text)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testDefaultSessionTimeoutIsTwoSeconds() {
        XCTAssertEqual(UpdateNudge.defaultSession.configuration.timeoutIntervalForRequest, 2)
        XCTAssertEqual(UpdateNudge.defaultSession.configuration.timeoutIntervalForResource, 2)
    }
}

extension UpdateNudgeTests {
    /// A fetch cancelled mid-flight (the share sheet was dismissed) must not stamp the 24 h timer,
    /// or the next share would skip the check for a day.
    func testCancelledFetchDoesNotStampLastCheck() async {
        FeedStub.mode = .hang
        let nudge = UpdateNudge(defaults: defaults, currentBuild: 3, session: session(timeout: 5))   // Sendable value
        let task = Task { await nudge.suffix() }
        try? await Task.sleep(for: .milliseconds(150))
        task.cancel()
        let text = await task.value
        XCTAssertNil(text)
        XCTAssertNil(defaults.object(forKey: UpdateNudge.lastCheckKey), "cancelled fetch stamped lastCheck")
    }
}
