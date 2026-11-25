import Foundation
import ImageIO

/// Chroma subsampling and luma quantization summary of a JPEG, read from its headers (no pixel decode).
public struct JPEGSummary: Equatable, Sendable {
    public var subsampling: String     // "4:4:4", "4:2:2", "4:2:0", or "HxV" for anything else
    public var lumaQ0: Int             // DC step
    public var lumaP50: Int            // lower median of the 64 steps
    public var lumaMax: Int
    public var nearestIJG: Int         // IJG (libjpeg) quality whose scaled Annex K table is closest (L1)
}

/// Describes an input file for the run log, so what Photos or Finder actually hands the extension
/// (format, size, JPEG quality) is visible after the fact.
public enum InputProbe {
    /// `<name> <uti> <w>x<h> <bytes>B[ jpeg(<sub> luma q0=.. p50=.. max=.. ijg~..)]`, or `<name> unreadable <bytes>B`.
    public static func describe(_ url: URL) -> String {
        let name = url.lastPathComponent
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(src) as String?,
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return "\(name) unreadable \(bytes)B" }
        var line = "\(name) \(type) \(width)x\(height) \(bytes)B"
        if type == "public.jpeg",
           let data = try? Data(contentsOf: url, options: .mappedIfSafe),
           let s = jpegSummary(data) {
            line += " jpeg(\(s.subsampling) luma q0=\(s.lumaQ0) p50=\(s.lumaP50) max=\(s.lumaMax) ijg~\(s.nearestIJG))"
        }
        return line
    }

    /// Parses DQT and SOF segments up to the first SOS. Nil when there is no SOF or no luma table.
    public static func jpegSummary(_ data: Data) -> JPEGSummary? {
        let d = [UInt8](data.prefix(1 << 20))   // headers live well inside the first megabyte
        guard d.count > 4, d[0] == 0xFF, d[1] == 0xD8 else { return nil }
        var tables: [Int: [Int]] = [:]
        var sof: (lumaTable: Int, h: Int, v: Int, chromaH: Int, chromaV: Int)?
        var i = 2
        while i + 3 < d.count {
            guard d[i] == 0xFF else { return nil }
            let marker = d[i + 1]
            if marker == 0xFF { i += 1; continue }                       // fill byte
            if marker == 0xD8 || marker == 0x01 || (0xD0...0xD7).contains(marker) { i += 2; continue }
            if marker == 0xD9 || marker == 0xDA { break }                // EOI / SOS: headers are done
            let length = Int(d[i + 2]) << 8 | Int(d[i + 3])
            let body = i + 4, end = i + 2 + length
            guard length >= 2, end <= d.count else { return nil }
            if marker == 0xDB {                                          // DQT: one or more tables
                var j = body
                while j < end {
                    let precision16 = d[j] >> 4 == 1, id = Int(d[j] & 0x0F)
                    let n = precision16 ? 128 : 64
                    guard j + 1 + n <= end else { return nil }
                    tables[id] = (0..<64).map { k in
                        precision16 ? Int(d[j + 1 + 2 * k]) << 8 | Int(d[j + 2 + 2 * k]) : Int(d[j + 1 + k])
                    }
                    j += 1 + n
                }
            } else if (0xC0...0xCF).contains(marker), marker != 0xC4, marker != 0xC8, marker != 0xCC {
                guard length >= 8 + 3 else { return nil }                // SOFn with at least one component
                let components = Int(d[body + 5])
                guard components >= 1, body + 6 + components * 3 <= end else { return nil }
                let y = body + 6
                let (h, v) = (Int(d[y + 1] >> 4), Int(d[y + 1] & 0x0F))
                let (ch, cv) = components >= 2 ? (Int(d[y + 4] >> 4), Int(d[y + 4] & 0x0F)) : (h, v)
                sof = (Int(d[y + 2]), h, v, ch, cv)
            }
            i = end
        }
        guard let sof, let luma = tables[sof.lumaTable] ?? tables[0] else { return nil }
        let sorted = luma.sorted()
        return JPEGSummary(subsampling: subsampling(sof.h, sof.v, sof.chromaH, sof.chromaV),
                           lumaQ0: luma[0], lumaP50: sorted[31], lumaMax: sorted[63],
                           nearestIJG: nearestIJG(luma))
    }

    private static func subsampling(_ h: Int, _ v: Int, _ ch: Int, _ cv: Int) -> String {
        guard ch > 0, cv > 0, h % ch == 0, v % cv == 0 else { return "\(h)x\(v)" }
        switch (h / ch, v / cv) {
        case (1, 1): return "4:4:4"
        case (2, 1): return "4:2:2"
        case (2, 2): return "4:2:0"
        case (let x, let y): return "\(x)x\(y)"
        }
    }

    /// JPEG Annex K luma table in zigzag order (the order DQT stores it).
    private static let annexKLuma: [Int] = [16, 11, 12, 14, 12, 10, 16, 14, 13, 14, 18, 17, 16, 19, 24, 40, 26, 24, 22, 22, 24, 49, 35, 37, 29, 40, 58, 51, 61, 60, 57, 51, 56, 55, 64, 72, 92, 78, 64, 68, 87, 69, 55, 56, 80, 109, 81, 87, 95, 98, 103, 104, 103, 62, 77, 113, 121, 112, 100, 120, 92, 101, 103, 99]

    static func nearestIJG(_ luma: [Int]) -> Int {
        var best = (q: 50, distance: Int.max)
        for q in 1...100 {
            let scale = q < 50 ? 5000 / q : 200 - 2 * q
            var distance = 0
            for k in 0..<64 {
                let step = min(255, max(1, (annexKLuma[k] * scale + 50) / 100))
                distance += abs(step - luma[k])
            }
            if distance < best.distance { best = (q, distance) }
        }
        return best.q
    }
}
