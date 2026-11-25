import AppKit
import SocialExportCore
import SwiftUI
import UserNotifications

/// Buy Me a Coffee link shown in the settings window; nil hides it.
enum TipLink {
    static let url: URL? = URL(string: "https://buymeacoffee.com/tonalphoto")
}

struct ContentView: View {
    @State private var model = SpecsModel()
    let updater: UpdaterModel

    var body: some View {
        Form {
            ForEach($model.specs) { $spec in
                SpecSection(spec: $spec)
            }
            Section {
                LabeledContent("Output folder", value: "~/Pictures/Socials (created on first export)")
                HStack {
                    Button("Reveal in Finder") { reveal() }
                    Button("Reset to defaults") { model.resetToDefaults() }
                }
            }
            Section("Notifications") {
                LabeledContent("Status", value: statusText)
                if model.notificationStatus != .authorized {
                    Button("Enable notifications") { Task { await model.requestNotifications() } }
                }
            }
            Section {
                LabeledContent("Version", value: UpdaterModel.versionString)
                HStack {
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                    if let tip = TipLink.url {
                        Link("Buy me a coffee", destination: tip)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .task { await model.refreshNotificationStatus() }
    }

    private var statusText: String {
        switch model.notificationStatus {
        case .authorized: "allowed"
        case .denied: "denied (enable in System Settings > Notifications)"
        case .notDetermined: "not asked yet"
        default: "limited"
        }
    }

    private func reveal() {
        let root = SpecsModel.outputRoot
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }
}

private struct SpecSection: View {
    @Binding var spec: ExportSpec

    private var ruleKind: Binding<Int> {
        Binding(
            get: { if case .width = spec.rule { 0 } else { 1 } },
            set: { spec.rule = $0 == 0 ? .width(pixels) : .longEdge(pixels) }
        )
    }

    private var pixels: Int {
        switch spec.rule {
        case .width(let v), .longEdge(let v): v
        }
    }

    private var pixelsBinding: Binding<Int> {
        Binding(
            get: { pixels },
            set: { v in
                let clamped = max(100, v)
                switch spec.rule {
                case .width: spec.rule = .width(clamped)
                case .longEdge: spec.rule = .longEdge(clamped)
                }
            }
        )
    }

    var body: some View {
        Section(spec.id.capitalized) {
            Picker("Rule", selection: ruleKind) {
                Text("Width").tag(0)
                Text("Longest edge").tag(1)
            }
            TextField("Pixels", value: pixelsBinding, format: .number.grouping(.never))
            HStack {
                Slider(value: $spec.quality, in: 0.5...1.0, step: 0.01) { Text("JPEG quality") }
                Text(spec.quality, format: .number.precision(.fractionLength(2))).monospacedDigit()
            }
        }
    }
}
