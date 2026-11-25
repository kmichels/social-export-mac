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

    /// Tags of the first IFD of a baseline TIFF: SHORT/LONG values decoded, other types reported as `[count]`.
    /// ImageIO does not expose SamplesPerPixel or ExtraSamples, so the TIFF tests read the file directly.
    static func tiffTags(_ url: URL) -> [UInt16: [UInt32]] {
        let d = [UInt8](try! Data(contentsOf: url))
        precondition(d.count > 8, "not a TIFF")
        let little = d[0] == 0x49
        func u16(_ o: Int) -> UInt32 {
            little ? UInt32(d[o]) | UInt32(d[o + 1]) << 8 : UInt32(d[o]) << 8 | UInt32(d[o + 1])
        }
        func u32(_ o: Int) -> UInt32 {
            little ? u16(o) | u16(o + 2) << 16 : u16(o) << 16 | u16(o + 2)
        }
        let ifd = Int(u32(4))
        var tags: [UInt16: [UInt32]] = [:]
        for i in 0..<Int(u16(ifd)) {
            let e = ifd + 2 + i * 12
            let tag = UInt16(u16(e)), type = u16(e + 2), count = Int(u32(e + 4))
            switch type {
            case 3: // SHORT
                let base = count <= 2 ? e + 8 : Int(u32(e + 8))
                tags[tag] = (0..<count).map { u16(base + $0 * 2) }
            case 4: // LONG
                let base = count <= 1 ? e + 8 : Int(u32(e + 8))
                tags[tag] = (0..<count).map { u32(base + $0 * 4) }
            default:
                tags[tag] = [UInt32(count)]
            }
        }
        return tags
    }
}
