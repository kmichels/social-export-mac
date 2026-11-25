public struct PixelSize: Equatable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public enum TargetSize {
    /// Output size for `input` under `rule`. Never upscales; rounds to the nearest pixel, minimum 1.
    public static func compute(input: PixelSize, rule: SizeRule) -> PixelSize {
        let scale: Double
        switch rule {
        case .width(let w):
            scale = Double(w) / Double(input.width)
        case .longEdge(let e):
            scale = Double(e) / Double(max(input.width, input.height))
        }
        guard scale < 1 else { return input }
        return PixelSize(width: scaled(input.width, by: scale), height: scaled(input.height, by: scale))
    }

    private static func scaled(_ value: Int, by scale: Double) -> Int {
        max(1, Int((Double(value) * scale).rounded()))
    }
}
