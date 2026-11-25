import Foundation
import os

public struct ExportFailure: Equatable, Sendable {
    public var input: URL
    public var error: ExportError
}

public struct ExportResult: Equatable, Sendable {
    public var written: [URL]
    public var failures: [ExportFailure]
    public var skipped: Int
    public var notificationText: String
}

public enum ExportRun {
    static let logger = Logger(subsystem: "com.tonalphoto.socialexport", category: "export")
    static let maxInFlight = 3

    /// Exports every input for every spec. A photo counts as exported only if all its specs succeeded; a failure
    /// is recorded and the run continues. Inputs are processed up to three at a time, except that inputs sharing
    /// an output name (case-folded, since ~/Pictures is case-insensitive) run one after another in input order,
    /// so "same name overwrites, last one wins" holds literally and a failed later input leaves the earlier files.
    /// Results keep input order.
    public static func run(inputs: [URL], specs: [ExportSpec], root: URL, skipped: Int = 0) async -> ExportResult {
        let start = Date()
        logger.info("run start: \(inputs.count) inputs, \(specs.count) specs, root \(root.path, privacy: .public)")

        // Chains of input indices that share an output name, in first-appearance order.
        var chainIndex: [String: Int] = [:]
        var chains: [[Int]] = []
        for (index, input) in inputs.enumerated() {
            let key = outputKey(input)
            if let c = chainIndex[key] {
                chains[c].append(index)
            } else {
                chainIndex[key] = chains.count
                chains.append([index])
            }
        }

        var perInput = [Int: (written: [URL], failure: ExportFailure?)](minimumCapacity: inputs.count)
        await withTaskGroup(of: [(Int, [URL], ExportFailure?)].self) { group in
            var next = 0
            func enqueue() {
                guard next < chains.count else { return }
                let chain = chains[next]
                next += 1
                group.addTask {
                    chain.map { index in
                        Task.isCancelled
                            ? (index, [], ExportFailure(input: inputs[index], error: .cancelled))
                            : exportOne(index: index, input: inputs[index], specs: specs, root: root)
                    }
                }
            }
            for _ in 0..<min(maxInFlight, chains.count) { enqueue() }
            for await results in group {
                for (index, written, failure) in results { perInput[index] = (written, failure) }
                enqueue()
            }
        }

        var written: [URL] = []
        var failures: [ExportFailure] = []
        for index in inputs.indices {
            guard let entry = perInput[index] else { continue }
            written.append(contentsOf: entry.written)
            if let failure = entry.failure { failures.append(failure) }
        }
        let exported = inputs.count - failures.count
        let text = notificationText(exported: exported, failures: failures, skipped: skipped)
        logger.info("run end: \(written.count) files, \(failures.count) failures, \(skipped) skipped, \(Date().timeIntervalSince(start), format: .fixed(precision: 2))s")
        return ExportResult(written: written, failures: failures, skipped: skipped, notificationText: text)
    }

    /// Case-folded, Unicode-normalized output stem: what the file system treats as the same file.
    static func outputKey(_ input: URL) -> String {
        (input.lastPathComponent as NSString).deletingPathExtension.precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func exportOne(index: Int, input: URL, specs: [ExportSpec], root: URL) -> (Int, [URL], ExportFailure?) {
        autoreleasepool {
            var written: [URL] = []
            for spec in specs {
                let destination = OutputPath.url(root: root, spec: spec, inputFilename: input.lastPathComponent)
                do {
                    let size = try ImageExporter(quality: spec.quality).export(source: input, to: destination, rule: spec.rule)
                    written.append(destination)
                    logger.info("wrote \(destination.path, privacy: .public) \(size.width)x\(size.height)")
                } catch let error as ExportError {
                    logger.error("export failed: input \(input.path, privacy: .public) -> \(destination.path, privacy: .public) rule \(String(describing: spec.rule), privacy: .public): \(String(describing: error), privacy: .public)")
                    return (index, written, ExportFailure(input: input, error: error))
                } catch {
                    logger.error("export failed: input \(input.path, privacy: .public) -> \(destination.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    return (index, written, ExportFailure(input: input, error: .write(destination, error.localizedDescription)))
                }
            }
            return (index, written, nil)
        }
    }

    static func notificationText(exported: Int, failures: [ExportFailure], skipped: Int) -> String {
        var text: String
        if let first = failures.first {
            text = "Social Export failed on \(first.input.lastPathComponent): \(describe(first.error))"
            if exported > 0 { text += " (\(exported) exported)" }
        } else {
            text = "Exported \(exported) photo\(exported == 1 ? "" : "s") to Socials"
        }
        if skipped > 0 { text += ", \(skipped) items skipped" }
        return text
    }

    private static func describe(_ error: ExportError) -> String {
        switch error {
        case .unreadable: "not a readable image"
        case .encodeFailed: "could not encode JPEG"
        case .write(_, let reason): reason
        case .cancelled: "cancelled"
        }
    }
}
