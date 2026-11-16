import SwiftUI

@main
struct MenuBarApp: App {
    @StateObject private var model: PrayerModel
    private let localizer: Localizing

    init() {
        do {
            let config = try BundleConfigLoader().load()
            let localizer = BundleLocalizer()
            let model = PrayerModel(
                config: config,
                source: HomeAssistantClient(config: config.homeAssistant),
                credentials: KeychainCredentialStore(store: KeychainTokenStore(service: config.bundleId)),
                makeLogin: {
                    LoopbackLogin(preferredPort: config.homeAssistant.loginPort,
                                  page: CallbackPage(l: localizer, appName: config.appName))
                },
                loginItem: MainAppLoginItem(),
                preferences: UserDefaultsPreferences(),
                notifier: UserNotificationService(stopTitle: localizer.t("action.stop")),
                planner: NotificationPlanner(l: localizer),
                updater: config.updatesEnabled ? SparkleUpdater() : nil,
                discovery: BonjourServerDiscovery(),
                sounds: SoundLibrary(bundleId: config.bundleId),
                player: AVSoundPlayer(),
                location: CoreLocationProvider(),
                aladhan: AladhanClient(baseURL: config.away.aladhanUrl)
            )
            _model = StateObject(wrappedValue: model)
            self.localizer = localizer
        } catch {
            fatalError("Invalid config.json: \(error)")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model, l: localizer)
        } label: {
            MenuBarLabel(model: model, l: localizer)
                .background(SetupLauncher(model: model))
        }
        .menuBarExtraStyle(.window)

        Window(localizer.t("setup.windowTitle", model.config.appName), id: SetupLauncher.windowId) {
            SetupWindow(model: model, l: localizer)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
