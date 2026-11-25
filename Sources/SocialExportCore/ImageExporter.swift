import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reads an image, bakes its EXIF orientation, converts to sRGB, resizes per a `SizeRule`, and writes a
/// JPEG with no metadata. Decodes downsampled (never at full size) so large inputs stay cheap in memory.
public struct ImageExporter: Sendable {
    public let quality: Double

    public init(quality: Double) {
        self.quality = quality
    }

    /// Returns the written pixel size.
    @discardableResult
    public func export(source: URL, to destination: URL, rule: SizeRule) throws -> PixelSize {
        try autoreleasepool {
            guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
                  CGImageSourceGetCount(src) > 0,
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                  let width = props[kCGImagePropertyPixelWidth] as? Int,
                  let height = props[kCGImagePropertyPixelHeight] as? Int
            else { throw ExportError.unreadable(source) }

            let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
            let oriented = (5...8).contains(orientation)
                ? PixelSize(width: height, height: width)
                : PixelSize(width: width, height: height)
            let target = TargetSize.compute(input: oriented, rule: rule)

            let thumbOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(target.width, target.height),
                kCGImageSourceShouldCache: false,
            ]
            guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOptions as CFDictionary),
                  let ctx = CGContext(data: nil, width: target.width, height: target.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { throw ExportError.unreadable(source) }

            let rect = CGRect(x: 0, y: 0, width: target.width, height: target.height)
            ctx.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [1, 1, 1, 1])!)
            ctx.fill(rect)
            ctx.interpolationQuality = .high
            ctx.draw(thumb, in: rect)
            guard let image = ctx.makeImage() else { throw ExportError.encodeFailed(destination) }

            try OutputPath.ensureDirectory(for: destination)
            guard let dest = CGImageDestinationCreateWithURL(destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
            else { throw ExportError.write(destination, "cannot create image destination") }
            CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw ExportError.encodeFailed(destination) }
            return target
        }
    }
}
