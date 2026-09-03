import SwiftUI

@main
struct CallDeskApp: App {
    // The delegate only routes external-display scene sessions; every
    // regular window keeps the plain SwiftUI lifecycle.
    @UIApplicationDelegateAdaptor(CallDeskAppDelegate.self) private var appDelegate

    private let dependencies: AppDependencies

    init() {
        // UI tests run against a seeded in-memory store so they stay
        // deterministic and never touch the on-disk database or the real
        // UserDefaults. The silent driver keeps calls fast and repeatable.
        if CommandLine.arguments.contains("-calldesk-ui-test") {
            dependencies = .production(
                persistence: PersistenceController(inMemory: true),
                settingsStore: InMemorySettingsStore(),
                speechDriver: SilentCallSpeechDriver(utteranceDuration: 0.1),
                seedSampleData: true
            )
        } else if CommandLine.arguments.contains("-calldesk-demo-seed") {
            // Showcase build: fills an empty store with the demo restaurant
            // data once, so the statistics and history screens are ready
            // for screenshots. Later normal launches keep the data.
            let showcaseSettingsStore = UserDefaultsSettingsStore()
            // The demo year holds ~60k calls, far beyond the default
            // 20k-cap; raise the cap so launch-time retention does not
            // evict most of the seeded history. The cap stays raised on
            // later normal launches because the settings are persisted.
            let showcaseHistorySettings = try? HistorySettings(
                retentionDays: 730,
                maximumRecordCount: 200_000
            )
            showcaseSettingsStore.save(
                CallDeskSettings(history: showcaseHistorySettings ?? .default)
            )
            dependencies = .production(
                settingsStore: showcaseSettingsStore,
                seedCatalog: CallDeskDemoData.makeCatalog()
            )
        } else {
            dependencies = .production()
        }
        // UIKit instantiates the external scene delegate on its own, so the
        // presenter is handed over through this single static hook.
        ExternalDisplaySceneDelegate.presenter = dependencies.externalDisplay
        // Launch housekeeping runs off the critical path so the first
        // screen appears immediately.
        let dependencies = self.dependencies
        Task {
            await dependencies.performStartupMaintenance()
        }
        // The Matcha model is loaded lazily when an operator first makes a
        // speech call. Loading its 126 MB model at launch competes with the
        // primary calling screen on older iPhones, including iPhone 8 Plus
        // on iOS 16, so startup must never preheat it in parallel.
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(dependencies: dependencies)
        }
    }
}
