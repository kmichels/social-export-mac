import Foundation

/// Persists the per-platform export specs. Production injects the app-group suite; tests inject a throwaway one.
public struct SpecStore: Sendable {
    public static let appGroupID = "85QL287QYW.com.tonalphoto.socialexport"
    static let key = "exportSpecs"

    /// `~/Pictures/Socials`. Resolved through `.picturesDirectory` so the sandboxed extension, which holds the
    /// Pictures entitlement, lands in the real folder rather than its container.
    public static var outputRoot: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0].appending(path: "Socials")
    }

    // UserDefaults is documented thread-safe but not marked Sendable.
    nonisolated(unsafe) private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func load() -> [ExportSpec] {
        guard let data = defaults.data(forKey: Self.key),
              let specs = try? JSONDecoder().decode([ExportSpec].self, from: data),
              !specs.isEmpty
        else { return ExportSpec.defaults }
        return specs
    }

    public func save(_ specs: [ExportSpec]) throws {
        defaults.set(try JSONEncoder().encode(specs), forKey: Self.key)
    }
}
