import Foundation
import Observation
import Sparkle

/// Owns the Sparkle updater for the host app. Automatic checks are enabled in Info.plist; this only
/// exposes the manual "Check for Updates…" action and the version string.
@MainActor @Observable
final class UpdaterModel {
    private(set) var canCheckForUpdates = false
    private let controller: SPUStandardUpdaterController
    private var observation: NSKeyValueObservation?

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        // KVO may fire off the main thread; the closure is explicitly @Sendable and hops to the main actor.
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { @Sendable [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheckForUpdates = value }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
