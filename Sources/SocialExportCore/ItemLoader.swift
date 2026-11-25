import Foundation
import UniformTypeIdentifiers
import os

/// Turns share-sheet `NSItemProvider`s into files on disk. Each item lands in its own `item_<i>/` subfolder
/// with its original filename, so two inputs with the same name survive loading and collide only at export.
public enum ItemLoader {
    static let logger = Logger(subsystem: "com.tonalphoto.socialexport", category: "loader")

    /// Main-actor bound because `NSItemProvider` is not `Sendable`; the waits are system callbacks, not CPU work.
    @MainActor
    public static func load(_ providers: [NSItemProvider], into dir: URL) async -> (files: [URL], skipped: Int, notes: [String]) {
        var files: [URL] = []
        var skipped = 0
        var notes: [String] = []
        for (index, provider) in providers.enumerated() {
            let itemDir = dir.appending(path: "item_\(index)")
            var file: URL?
            if let typeID = concreteImageType(of: provider) {
                let preferredName = await originalName(of: provider)
                let (loaded, note) = await copyFileRepresentation(of: provider, type: typeID, preferredName: preferredName, into: itemDir)
                file = loaded
                if let note { notes.append("item \(index): \(note)") }
            }
            if file == nil, provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                // Photos.app on macOS shares a file URL to its temporary JPEG export; on macOS 27 the public.jpeg
                // file representation fails even though it is registered, so the URL is the reliable path.
                let (loaded, note) = await copyFileURLItem(of: provider, into: itemDir)
                file = loaded
                if let note { notes.append("item \(index): \(note)") }
            }
            if let file {
                files.append(file)
            } else {
                skipped += 1
                if concreteImageType(of: provider) == nil, !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    notes.append("item \(index): no image or file URL among \(provider.registeredTypeIdentifiers)")
                }
                logger.info("skipping item \(index): \(provider.registeredTypeIdentifiers, privacy: .public)")
            }
        }
        return (files, skipped, notes)
    }

    /// Loads a `public.file-url` item and copies the file if it is an image (by extension or resource type).
    @MainActor
    private static func copyFileURLItem(of provider: NSItemProvider, into itemDir: URL) async -> (URL?, String?) {
        await withCheckedContinuation { continuation in
            _ = provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { @Sendable item, error in
                guard let url = (item as? URL) ?? (item as? Data).flatMap({ URL(dataRepresentation: $0, relativeTo: nil) }) else {
                    let note = "file-url item failed: \(error?.localizedDescription ?? "no url")"
                    logger.error("\(note, privacy: .public)")
                    continuation.resume(returning: (nil, note))
                    return
                }
                let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? UTType(filenameExtension: url.pathExtension)
                guard type?.conforms(to: .image) == true else {
                    let note = "file-url \(url.lastPathComponent) is not an image"
                    logger.info("\(note, privacy: .public)")
                    continuation.resume(returning: (nil, note))
                    return
                }
                let destination = itemDir.appending(path: url.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(at: itemDir, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: (destination, nil))
                } catch {
                    let note = "copy of file-url \(url.path) failed: \(error.localizedDescription)"
                    logger.error("\(note, privacy: .public)")
                    continuation.resume(returning: (nil, note))
                }
            }
        }
    }

    /// Photos registers concrete ids like `public.jpeg`; asking for abstract `public.image` fails there.
    static func concreteImageType(of provider: NSItemProvider) -> String? {
        provider.registeredTypeIdentifiers.first { id in
            UTType(id)?.conforms(to: .image) == true
        }
    }

    /// The temp file handed to `loadFileRepresentation` is named generically ("JPEG image.jpeg"). The original
    /// name comes from `suggestedName`, else from a `public.file-url` representation when the provider has one.
    @MainActor
    static func originalName(of provider: NSItemProvider) async -> String? {
        if let suggested = provider.suggestedName, !suggested.isEmpty { return suggested }
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { @Sendable item, _ in
                let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                continuation.resume(returning: url?.lastPathComponent)
            }
        }
    }

    static func filename(preferredName: String?, type: String, tempURL: URL) -> String {
        let ext = UTType(type)?.preferredFilenameExtension ?? tempURL.pathExtension
        if let preferredName, !preferredName.isEmpty {
            return (preferredName as NSString).pathExtension.isEmpty ? "\(preferredName).\(ext)" : preferredName
        }
        return tempURL.lastPathComponent.isEmpty ? "image.\(ext)" : tempURL.lastPathComponent
    }

    /// The URL handed to the completion closure is only valid inside it, so the copy happens there.
    @MainActor
    private static func copyFileRepresentation(of provider: NSItemProvider, type: String, preferredName: String?, into itemDir: URL) async -> (URL?, String?) {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { @Sendable url, error in
                guard let url else {
                    let note = "loadFileRepresentation(\(type)) failed: \(error?.localizedDescription ?? "nil url")"
                    logger.error("\(note, privacy: .public)")
                    continuation.resume(returning: (nil, note))
                    return
                }
                let destination = itemDir.appending(path: filename(preferredName: preferredName, type: type, tempURL: url))
                do {
                    try FileManager.default.createDirectory(at: itemDir, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: (destination, nil))
                } catch {
                    let note = "copy of \(type) representation to \(destination.path) failed: \(error.localizedDescription)"
                    logger.error("\(note, privacy: .public)")
                    continuation.resume(returning: (nil, note))
                }
            }
        }
    }
}
