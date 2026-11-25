/// How an output is sized relative to the input. Never upscales.
public enum SizeRule: Codable, Equatable, Sendable {
    /// Fixed width in pixels, height proportional (Instagram, Threads).
    case width(Int)
    /// Longest edge in pixels, other edge proportional (Facebook).
    case longEdge(Int)
}

/// Output file format. JPEG is the default everywhere; `tiff8` is 8-bit RGB, uncompressed, no alpha.
public enum OutputFormat: String, Codable, CaseIterable, Sendable {
    case jpeg
    case tiff8

    public var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .tiff8: "tif"
        }
    }
}

/// One platform's export recipe. Stored as JSON in the app-group defaults.
public struct ExportSpec: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var folder: String
    public var rule: SizeRule
    /// JPEG quality, 0...1. Ignored for TIFF.
    public var quality: Double
    public var format: OutputFormat

    public init(id: String, folder: String, rule: SizeRule, quality: Double, format: OutputFormat = .jpeg) {
        self.id = id
        self.folder = folder
        self.rule = rule
        self.quality = quality
        self.format = format
    }

    /// Specs stored by 1.0.x have no `format` key; they load as JPEG. Encoding stays synthesized.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        folder = try c.decode(String.self, forKey: .folder)
        rule = try c.decode(SizeRule.self, forKey: .rule)
        quality = try c.decode(Double.self, forKey: .quality)
        format = try c.decodeIfPresent(OutputFormat.self, forKey: .format) ?? .jpeg
    }

    public static let defaults: [ExportSpec] = [
        ExportSpec(id: "instagram", folder: "instagram", rule: .width(1080), quality: 0.85),
        ExportSpec(id: "threads", folder: "threads", rule: .width(1080), quality: 0.85),
        ExportSpec(id: "facebook", folder: "facebook", rule: .longEdge(2048), quality: 0.95),
    ]
}
