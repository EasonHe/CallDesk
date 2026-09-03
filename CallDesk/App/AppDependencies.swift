import Foundation

@MainActor
struct AppDependencies {
    let workspaces: any WorkspaceRepository
    let boards: any CallBoardRepository
    let actions: any CallActionRepository
    let templates: any VoiceTemplateRepository
    let history: any CallHistoryRepository
    let settings: CallDeskSettings
    let settingsStore: any SettingsStore
    let audioEnvironment: any AudioEnvironmentMonitoring
    let audioClips: any AudioClipStoring
    let audioPacks: any AudioPackStoring
    let callService: any CallService
    let calledMarkers: any CalledMarkersStoring
    let startupDiagnostics: StartupDiagnostics
    let externalDisplay: ExternalDisplayPresenter
    /// One-time background work that fills an empty store with demo data;
    /// UI must wait for it before showing screens that read the data.
    let initialDataSeed: Task<Void, Never>?

    init(
        workspaces: any WorkspaceRepository,
        boards: any CallBoardRepository,
        actions: any CallActionRepository,
        templates: any VoiceTemplateRepository,
        history: any CallHistoryRepository,
        settings: CallDeskSettings = .default,
        settingsStore: (any SettingsStore)? = nil,
        audioEnvironment: (any AudioEnvironmentMonitoring)? = nil,
        audioClips: (any AudioClipStoring)? = nil,
        audioPacks: (any AudioPackStoring)? = nil,
        callService: (any CallService)? = nil,
        calledMarkers: (any CalledMarkersStoring)? = nil,
        startupDiagnostics: StartupDiagnostics = StartupDiagnostics(),
        initialDataSeed: Task<Void, Never>? = nil
    ) {
        self.workspaces = workspaces
        self.boards = boards
        self.actions = actions
        self.templates = templates
        self.history = history
        self.settings = settings
        self.initialDataSeed = initialDataSeed
        let resolvedSettingsStore = settingsStore ?? InMemorySettingsStore(settings: settings)
        self.settingsStore = resolvedSettingsStore
        let resolvedAudioEnvironment = audioEnvironment ?? FixedAudioEnvironmentMonitor()
        self.audioEnvironment = resolvedAudioEnvironment
        let resolvedAudioPacks = audioPacks ?? FileSystemAudioPackStore()
        self.audioPacks = resolvedAudioPacks
        let resolvedAudioClips = audioClips ?? BundledAudioClipStore(
            userClips: FileSystemAudioClipStore(),
            packs: resolvedAudioPacks
        )
        self.audioClips = resolvedAudioClips
        let resolvedCallService = callService ?? DefaultCallService(
            actions: actions,
            history: history,
            settingsStore: resolvedSettingsStore,
            audioClips: resolvedAudioClips,
            audioEnvironment: resolvedAudioEnvironment
        )
        self.callService = resolvedCallService
        self.calledMarkers = calledMarkers ?? InMemoryCalledMarkersStore()
        self.startupDiagnostics = startupDiagnostics
        self.externalDisplay = ExternalDisplayPresenter(
            callService: resolvedCallService,
            history: history,
            settingsStore: resolvedSettingsStore
        )
    }

    init(repositories: InMemoryRepositories, settings: CallDeskSettings = .default) {
        self.init(
            workspaces: repositories.workspaces,
            boards: repositories.boards,
            actions: repositories.actions,
            templates: repositories.templates,
            history: repositories.history,
            settings: settings
        )
    }

    init(repositories: CoreDataRepositories, settings: CallDeskSettings = .default) {
        self.init(
            workspaces: repositories.workspaces,
            boards: repositories.boards,
            actions: repositories.actions,
            templates: repositories.templates,
            history: repositories.history,
            settings: settings
        )
    }

    /// Production runs on Core Data so boards, actions, and history survive
    /// app restarts. No sample data is written by default: a fresh install
    /// starts with an empty desk. UI tests opt into the sample catalog so
    /// their flows have boards and actions to drive, and the demo catalog
    /// powers the showcase store used for screenshots.
    static func production(
        persistence: PersistenceController = PersistenceController(),
        settingsStore: any SettingsStore = UserDefaultsSettingsStore(),
        speechDriver: (any CallSpeechDriving)? = nil,
        seedSampleData: Bool = false,
        seedCatalog: CallDeskSampleData.Catalog? = nil
    ) -> AppDependencies {
        let repositories = CoreDataRepositories(persistence: persistence)
        // Repair the obsolete bundled clip names from the first showcase
        // catalog. This is scoped to fixed demo IDs and is a no-op for all
        // current catalogs and user-created content.
        Task(priority: .utility) {
            _ = try? await repositories.store.migrateLegacyDemoAudioClipReferences()
        }
        let catalogToSeed = seedCatalog ?? (seedSampleData ? CallDeskSampleData.catalog : nil)
        // Seed work runs off the launch path so a year of demo records can
        // never stall the first screen; the root view waits for the task
        // before rendering anything that reads the seeded data.
        var initialDataSeed: Task<Void, Never>?
        if let catalogToSeed {
            initialDataSeed = Task {
                _ = try? await repositories.store.seedInitialDataIfNeeded(catalog: catalogToSeed)
            }
        }
        // The launch snapshot only seeds `settings`; the call service and
        // the speech driver read the latest settings from the store on every
        // call, so changes take effect without a restart.
        let settings = settingsStore.load()
        // The system monitor mirrors the live output route (Bluetooth,
        // AirPlay, headphones) for history records and the Settings screen,
        // and reports interruptions to the call service.
        let audioEnvironment = SystemAudioEnvironmentMonitor()
        // Imported audio clips live on disk so actions only keep a file-name
        // reference; the composite store resolves bundled defaults first,
        // then falls back to user imports on disk. Pack clips are addressed
        // as "<packUUID>/<fileName>" and live in a separate namespace.
        let audioPacks = FileSystemAudioPackStore()
        let audioClips = BundledAudioClipStore(
            userClips: FileSystemAudioClipStore(),
            packs: audioPacks
        )
        // Production announces calls out loud, so the call service drives the
        // real speech synthesizer instead of the silent placeholder driver.
        // UI tests inject a silent driver here to stay fast and deterministic.
        let callService = DefaultCallService(
            actions: repositories.actions,
            history: repositories.history,
            settingsStore: settingsStore,
            speechDriver: speechDriver ?? AVSpeechSynthesizerSpeechDriver(),
            audioClips: audioClips,
            audioEnvironment: audioEnvironment
        )
        return AppDependencies(
            workspaces: repositories.workspaces,
            boards: repositories.boards,
            actions: repositories.actions,
            templates: repositories.templates,
            history: repositories.history,
            settings: settings,
            settingsStore: settingsStore,
            audioEnvironment: audioEnvironment,
            audioClips: audioClips,
            audioPacks: audioPacks,
            callService: callService,
            calledMarkers: UserDefaultsCalledMarkersStore(),
            startupDiagnostics: persistence.diagnostics,
            initialDataSeed: initialDataSeed
        )
    }

    static func preview() -> AppDependencies {
        AppDependencies(repositories: checkedSampleRepositories())
    }

    static func test(
        repositories: InMemoryRepositories,
        settings: CallDeskSettings = .default
    ) -> AppDependencies {
        AppDependencies(repositories: repositories, settings: settings)
    }

    /// One-off housekeeping at launch: applies the configured history
    /// retention policy so stale records left from before the last run are
    /// trimmed even if no call happens in this session. Mirrors the policy
    /// the call service already enforces after every saved call.
    func performStartupMaintenance() async {
        let historySettings = settingsStore.load().history
        guard let policy = try? HistoryRetentionPolicy(
            retentionDays: historySettings.retentionDays > 0 ? historySettings.retentionDays : nil,
            maximumRecordCount: historySettings.maximumRecordCount > 0 ? historySettings.maximumRecordCount : nil
        ), policy.retentionDays != nil || policy.maximumRecordCount != nil else {
            return
        }
        // Best effort, exactly like the per-call retention pass.
        _ = try? await history.enforceRetention(policy, now: Date())
    }

    private static func checkedSampleRepositories() -> InMemoryRepositories {
        do {
            return try InMemoryRepositories.sample()
        } catch {
            preconditionFailure("Invalid CallDesk sample repositories: \(error)")
        }
    }
}
