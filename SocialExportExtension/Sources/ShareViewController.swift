import AppKit
import SocialExportCore
import UserNotifications
import os

/// Share-sheet entry point. No controls: a spinner while the run happens, one notification at the end.
final class ShareViewController: NSViewController {
    private let logger = Logger(subsystem: "com.tonalphoto.socialexport", category: "extension")
    private var started = false
    private var exportTask: Task<Void, Never>?

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 64))
        let spinner = NSProgressIndicator(frame: NSRect(x: 20, y: 20, width: 24, height: 24))
        spinner.style = .spinning
        spinner.startAnimation(nil)
        let label = NSTextField(labelWithString: "Exporting for Instagram, Threads and Facebook…")
        label.frame = NSRect(x: 54, y: 24, width: 200, height: 18)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.lineBreakMode = .byTruncatingTail
        container.addSubview(spinner)
        container.addSubview(label)
        view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !started else { return }
        started = true
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?.flatMap { $0.attachments ?? [] } ?? []
        logger.info("share started with \(providers.count) items")
        exportTask = Task { [weak self] in
            let text = await Self.export(providers: providers)
            guard !Task.isCancelled else { return }
            await self?.finish(with: text)
        }
    }

    /// The host dismissed the sheet (Escape, or the share was cancelled): stop starting new exports.
    override func viewWillDisappear() {
        super.viewWillDisappear()
        exportTask?.cancel()
    }

    /// Item loading stays on the main actor (providers are not Sendable); `ExportRun.run` is nonisolated and
    /// does the image work off the main actor.
    @MainActor
    private static func export(providers: [NSItemProvider]) async -> String {
        let start = Date()
        let dir = FileManager.default.temporaryDirectory.appending(path: "social-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let types = providers.map { $0.registeredTypeIdentifiers.joined(separator: ",") }
        let groupDefaults = UserDefaults(suiteName: SpecStore.appGroupID) ?? .standard
        // The update check runs alongside the export so it adds no wall-clock time (capped at 2 s anyway).
        let currentBuild = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
        let checker = UpdateNudge(defaults: groupDefaults, currentBuild: currentBuild)   // Sendable; built on the main actor
        async let nudge = checker.suffix()
        let (files, skipped, notes) = await ItemLoader.load(providers, into: dir)
        guard !Task.isCancelled else { return "" }   // sheet dismissed while loading: nothing is written, nothing is posted
        let specs = SpecStore(defaults: groupDefaults).load()
        let result = await ExportRun.run(inputs: files, specs: specs, root: SpecStore.outputRoot, skipped: skipped)
        let suffix = await nudge
        var text = result.notificationText
        if result.failures.isEmpty, !result.written.isEmpty, let suffix { text += suffix }
        let summary = "share finished in \(String(format: "%.2f", Date().timeIntervalSince(start)))s: \(text)"
        Logger(subsystem: "com.tonalphoto.socialexport", category: "extension").info("\(summary, privacy: .public)")
        appendDiagnostic("\(Date()) items=\(providers.count) types=\(types) loaded=\(files.map(\.lastPathComponent)) notes=\(notes) nudge=\(suffix ?? "none") \(summary)")
        return text
    }

    /// One line per run in `~/Pictures/Socials/.social-export.log`, readable over ssh where the unified log is not.
    private static func appendDiagnostic(_ line: String) {
        let url = SpecStore.outputRoot.appending(path: ".social-export.log")
        try? FileManager.default.createDirectory(at: SpecStore.outputRoot, withIntermediateDirectories: true)
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    @MainActor
    private func finish(with text: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Social Export"
        content.body = text
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            logger.error("notification failed: \(error.localizedDescription, privacy: .public)")
        }
        extensionContext?.completeRequest(returningItems: [])
    }
}
