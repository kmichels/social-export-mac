import Foundation
import os

/// Once-a-day appcast check for the Share extension, which has no Sparkle of its own. Returns the nudge
/// text when a newer build is published; every failure is silent and still stamps `lastCheck` so a
/// broken feed is not fetched on every share.
public struct UpdateNudge: Sendable {
    public static let lastCheckKey = "updateLastCheck"
    public static let latestBuildKey = "updateLatestBuild"
    static let logger = Logger(subsystem: "com.tonalphoto.socialexport", category: "update")

    /// Bounded so the check never delays the share notification by more than this.
    public static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 2
        return URLSession(configuration: config)
    }()

    let feedURL: URL
    nonisolated(unsafe) let defaults: UserDefaults   // UserDefaults is thread-safe but not marked Sendable
    let currentBuild: Int
    let session: URLSession
    let now: @Sendable () -> Date

    public init(feedURL: URL = AppcastCheck.feedURL, defaults: UserDefaults, currentBuild: Int,
                session: URLSession = UpdateNudge.defaultSession, now: @escaping @Sendable () -> Date = Date.init) {
        self.feedURL = feedURL
        self.defaults = defaults
        self.currentBuild = currentBuild
        self.session = session
        self.now = now
    }

    public func suffix() async -> String? {
        let lastCheck = defaults.object(forKey: Self.lastCheckKey) as? Date
        if AppcastCheck.shouldCheck(now: now(), lastCheck: lastCheck) {
            switch await fetchLatestBuild() {
            case .cancelled:
                break   // the share was dismissed mid-fetch; leave the timer alone so the next share checks again
            case .completed(let latest):
                defaults.set(now(), forKey: Self.lastCheckKey)   // stamped on success and on errors alike, so a broken feed is not hammered
                if let latest { defaults.set(latest, forKey: Self.latestBuildKey) }
            }
        }
        let stored = defaults.object(forKey: Self.latestBuildKey) as? Int
        return AppcastCheck.nudgeText(current: currentBuild, latest: stored)
    }

    private enum Fetch { case completed(Int?), cancelled }

    private func fetchLatestBuild() async -> Fetch {
        do {
            let (data, response) = try await session.data(from: feedURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                Self.logger.info("appcast fetch: HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return .completed(nil)
            }
            let latest = AppcastCheck.latestBuild(in: data)
            Self.logger.info("appcast fetch: latest build \(latest ?? -1), current \(currentBuild)")
            return .completed(latest)
        } catch is CancellationError {
            return .cancelled
        } catch let error as URLError where error.code == .cancelled {
            return .cancelled
        } catch {
            Self.logger.info("appcast fetch failed: \(error.localizedDescription, privacy: .public)")
            return .completed(nil)
        }
    }
}
