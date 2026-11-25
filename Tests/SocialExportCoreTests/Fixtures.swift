import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// Generates test images at runtime so no binary fixtures are committed.
enum Fixtures {
    static func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "social-export-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Writes a gradient image with the given color space, EXIF orientation and a GPS tag (so metadata
    /// stripping can be observed). Returns the file URL.
    static func make(width: Int, height: Int,
                     colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!,
                     orientation: Int = 1,
                     type: UTType = .jpeg,
                     name: String = "fixture",
                     in dir: URL? = nil) -> URL {
        let image = gradient(width: width, height: height, colorSpace: colorSpace)
        let url = (dir ?? tempDir()).appending(path: "\(name).\(type.preferredFilenameExtension ?? "img")")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        let props: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 51.5, kCGImagePropertyGPSLatitudeRef: "N"],
            kCGImageDestinationLossyCompressionQuality: 0.9,
        ]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        precondition(CGImageDestinationFinalize(dest), "fixture write failed for \(type.identifier)")
        return url
    }

    static func gradient(width: Int, height: Int, colorSpace: CGColorSpace) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        let colors = [CGColor(colorSpace: colorSpace, components: [1, 0.2, 0.1, 1])!,
                      CGColor(colorSpace: colorSpace, components: [0.1, 0.3, 1, 1])!]
        let grad = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: width, y: height), options: [])
        return ctx.makeImage()!
    }

    /// Top-level ImageIO properties of the image at `url`.
    static func props(_ url: URL) -> [CFString: Any] {
        let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
        return CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
    }

    static func pixelSize(_ url: URL) -> (Int, Int) {
        let p = props(url)
        return (p[kCGImagePropertyPixelWidth] as! Int, p[kCGImagePropertyPixelHeight] as! Int)
    }

    static func fileSize(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
    }
}
