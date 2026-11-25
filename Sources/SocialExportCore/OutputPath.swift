import Foundation

public enum ExportError: Error, Equatable, Sendable {
    case unreadable(URL)
    case encodeFailed(URL)
    case write(URL, String)
    /// The surrounding task was cancelled before this input was exported.
    case cancelled
}

public enum OutputPath {
    /// `root/<spec.folder>/<input stem>.jpg`. The stem keeps interior dots; only the last extension is dropped.
    public static func url(root: URL, spec: ExportSpec, inputFilename: String) -> URL {
        let stem = (inputFilename as NSString).deletingPathExtension
        return root.appending(path: spec.folder).appending(path: stem + ".jpg")
    }

    /// Creates the parent directory of `url` (and intermediates). Errors map to `ExportError.write`.
    public static func ensureDirectory(for url: URL, fm: FileManager = .default) throws {
        let dir = url.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw ExportError.write(url, error.localizedDescription)
        }
    }
}
