import SwiftUI

@main
struct SocialExportApp: App {
    @State private var updater = UpdaterModel()

    var body: some Scene {
        Window("Social Export", id: "main") {
            ContentView(updater: updater)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
        }
    }
}
