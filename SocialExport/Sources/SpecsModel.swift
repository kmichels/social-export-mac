import Foundation
import Observation
import SocialExportCore
import UserNotifications

@MainActor @Observable
final class SpecsModel {
    var specs: [ExportSpec] {
        didSet { try? store.save(specs) }
    }
    var notificationStatus: UNAuthorizationStatus = .notDetermined

    private let store: SpecStore

    init(store: SpecStore = SpecStore(defaults: UserDefaults(suiteName: SpecStore.appGroupID) ?? .standard)) {
        self.store = store
        self.specs = store.load()
    }

    func resetToDefaults() {
        specs = ExportSpec.defaults
    }

    func refreshNotificationStatus() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refreshNotificationStatus()
    }

    static var outputRoot: URL { SpecStore.outputRoot }
}
