import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reads an image, bakes its EXIF orientation, converts to sRGB, resizes per a `SizeRule`, and writes a
/// JPEG or an 8-bit uncompressed RGB TIFF with no metadata. Decodes downsampled (never at full size) so large
/// inputs stay cheap in memory.
public struct ImageExporter: Sendable {
    public let quality: Double
    public let format: OutputFormat

    public init(quality: Double, format: OutputFormat = .jpeg) {
        self.quality = quality
        self.format = format
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
            let (type, properties) = encoding
            guard let dest = CGImageDestinationCreateWithURL(destination as CFURL, type.identifier as CFString, 1, nil)
            else { throw ExportError.write(destination, "cannot create image destination") }
            // The context is 8-bit noneSkipLast: ImageIO writes 3 samples per pixel and drops the skip byte,
            // so neither format gains an alpha channel. No source properties are copied (metadata stays out).
            CGImageDestinationAddImage(dest, image, properties as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw ExportError.encodeFailed(destination) }
            return target
        }
    }

    /// Destination type and per-image properties. TIFF compression is set explicitly to none (1) so a change in
    /// ImageIO's default cannot silently make the "lossless" option compressed or lossy.
    private var encoding: (UTType, [CFString: Any]) {
        switch format {
        case .jpeg:
            (.jpeg, [kCGImageDestinationLossyCompressionQuality: quality])
        case .tiff8:
            (.tiff, [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 1]])
        }
    }
}
