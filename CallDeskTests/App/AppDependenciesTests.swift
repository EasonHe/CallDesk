import Foundation
import Testing
@testable import CallDesk

@MainActor
@Suite("App dependencies")
struct AppDependenciesTests {
    @Test("Production dependencies run on Core Data without sample data")
    func productionDependenciesUseCoreDataWithoutSampleData() async throws {
        let dependencies = AppDependencies.production(
            persistence: PersistenceController(inMemory: true),
            settingsStore: InMemorySettingsStore(settings: .default)
        )

        #expect(dependencies.workspaces is CoreDataWorkspaceRepository)
        #expect(dependencies.boards is CoreDataCallBoardRepository)
        #expect(dependencies.actions is CoreDataCallActionRepository)
        #expect(dependencies.templates is CoreDataVoiceTemplateRepository)
        #expect(dependencies.history is CoreDataCallHistoryRepository)

        let workspaces = try await dependencies.workspaces.fetchAll()
        #expect(workspaces.isEmpty)
        #expect(try await dependencies.history.fetch(.all).isEmpty)
        #expect(dependencies.settings == .default)
    }

    @Test("Production dependencies seed the base catalog when opted in")
    func productionDependenciesSeedCatalogWhenOptedIn() async throws {
        let dependencies = AppDependencies.production(
            persistence: PersistenceController(inMemory: true),
            seedSampleData: true
        )

        await dependencies.initialDataSeed?.value
        let workspaces = try await dependencies.workspaces.fetchAll()
        #expect(!workspaces.isEmpty)
        let boards = try await dependencies.boards.fetchAll(
            workspaceID: try #require(workspaces.first).id,
            includeArchived: true
        )
        #expect(!boards.isEmpty)
    }

    @Test("Preview dependencies stay on isolated in-memory repositories")
    func previewDependenciesStayInMemory() {
        let dependencies = AppDependencies.preview()

        #expect(dependencies.workspaces is InMemoryWorkspaceRepository)
        #expect(dependencies.history is InMemoryCallHistoryRepository)
    }

    @Test("Preview dependencies never share mutable state between calls")
    func previewDependenciesNeverShareMutableState() async throws {
        let first = AppDependencies.preview()
        let second = AppDependencies.preview()

        let extraWorkspace = try Workspace(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 200)),
            name: "Isolated Preview Workspace"
        )
        try await first.workspaces.save(extraWorkspace)

        let firstNames = try await first.workspaces.fetchAll().map(\.name)
        let secondNames = try await second.workspaces.fetchAll().map(\.name)
        #expect(firstNames.contains("Isolated Preview Workspace"))
        #expect(!secondNames.contains("Isolated Preview Workspace"))
    }

    @Test("Test dependencies use the injected repositories and settings")
    func testDependenciesUseInjectedRepositoriesAndSettings() async throws {
        let repositories = try InMemoryRepositories.empty()
        let settings = CallDeskSettings(
            history: try HistorySettings(retentionDays: 7, maximumRecordCount: 100)
        )
        let dependencies = AppDependencies.test(
            repositories: repositories,
            settings: settings
        )

        let workspaces = try await dependencies.workspaces.fetchAll()
        #expect(workspaces.isEmpty)
        #expect(dependencies.settings.history.retentionDays == 7)
    }

    @Test("Startup maintenance trims history to the configured maximum")
    func startupMaintenanceTrimsHistoryToMaximum() async throws {
        let repositories = try InMemoryRepositories.empty()
        let settings = CallDeskSettings(
            history: try HistorySettings(retentionDays: 0, maximumRecordCount: 1)
        )
        let dependencies = AppDependencies.test(repositories: repositories, settings: settings)
        for index in 0..<3 {
            try await repositories.history.save(
                try CallRecord(
                    actionTitleSnapshot: "A00\(index)",
                    spokenTextSnapshot: "Please call A00\(index)",
                    startedAt: Date(timeIntervalSinceReferenceDate: Double(index)),
                    completedAt: Date(timeIntervalSinceReferenceDate: Double(index)),
                    result: .completed
                )
            )
        }

        await dependencies.performStartupMaintenance()

        let records = try await repositories.history.fetch(.all)
        #expect(records.count == 1)
        #expect(records.first?.actionTitleSnapshot == "A002")
    }

    @Test("Startup maintenance leaves history alone when limits are disabled")
    func startupMaintenanceLeavesHistoryAloneWhenDisabled() async throws {
        let repositories = try InMemoryRepositories.empty()
        let settings = CallDeskSettings(
            history: try HistorySettings(retentionDays: 0, maximumRecordCount: 0)
        )
        let dependencies = AppDependencies.test(repositories: repositories, settings: settings)
        for index in 0..<3 {
            try await repositories.history.save(
                try CallRecord(
                    actionTitleSnapshot: "A00\(index)",
                    spokenTextSnapshot: "Please call A00\(index)",
                    startedAt: Date(timeIntervalSinceReferenceDate: Double(index)),
                    completedAt: Date(timeIntervalSinceReferenceDate: Double(index)),
                    result: .completed
                )
            )
        }

        await dependencies.performStartupMaintenance()

        #expect(try await repositories.history.fetch(.all).count == 3)
    }

    @Test("The external display presenter is wired to the shared call service")
    func externalDisplayPresenterIsWired() throws {
        let repositories = try InMemoryRepositories.empty()
        let dependencies = AppDependencies.test(repositories: repositories)

        #expect(dependencies.externalDisplay.presentation.liveCall == dependencies.callService.liveCallState)
        #expect(!dependencies.externalDisplay.isConnected)
    }
}
