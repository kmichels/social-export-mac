/// How an output is sized relative to the input. Never upscales.
public enum SizeRule: Codable, Equatable, Sendable {
    /// Fixed width in pixels, height proportional (Instagram, Threads).
    case width(Int)
    /// Longest edge in pixels, other edge proportional (Facebook).
    case longEdge(Int)
}

/// One platform's export recipe. Stored as JSON in the app-group defaults.
public struct ExportSpec: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var folder: String
    public var rule: SizeRule
    public var quality: Double

    public init(id: String, folder: String, rule: SizeRule, quality: Double) {
        self.id = id
        self.folder = folder
        self.rule = rule
        self.quality = quality
    }

    public static let defaults: [ExportSpec] = [
        ExportSpec(id: "instagram", folder: "instagram", rule: .width(1080), quality: 0.85),
        ExportSpec(id: "threads", folder: "threads", rule: .width(1080), quality: 0.85),
        ExportSpec(id: "facebook", folder: "facebook", rule: .longEdge(2048), quality: 0.95),
    ]
}
