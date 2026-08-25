import Foundation
import Testing
@testable import CallDesk

@Suite("Core Data persistence stack")
struct CoreDataPersistenceTests {
    @Test("Data saved through one repository set survives recreating the repositories")
    func dataSurvivesRepositoryRecreation() async throws {
        let persistence = PersistenceController(inMemory: true)
        let workspace = try Workspace(id: coreDataFixedUUID(1), name: "Persistent")
        try await CoreDataRepositories(persistence: persistence).workspaces.save(workspace)

        let reopened = CoreDataRepositories(persistence: persistence)
        #expect(try await reopened.workspaces.workspace(id: workspace.id) == workspace)
    }

    @Test("All six repositories observe mutations through the shared container")
    func repositoriesShareOneContainer() async throws {
        let context = CoreDataTestContext()
        let boardID = try await context.makeBoard(workspaceValue: 2, boardValue: 3)
        try await context.repositories.actions.save(
            try CallAction(id: coreDataFixedUUID(4), boardID: boardID, title: "A001", speechText: "A001")
        )

        await #expect(
            throws: RepositoryError.relationshipConflict(message: "Cannot delete a board that contains actions.")
        ) {
            try await context.repositories.boards.delete(id: boardID)
        }
        #expect(try await context.repositories.workspaces.fetchAll().count == 1)
    }

    @Test("Seeding writes the catalog once and never repeats")
    func seedingIsIdempotent() async throws {
        let context = CoreDataTestContext()
        let catalog = CallDeskSampleData.catalog

        #expect(try await context.repositories.store.seedInitialDataIfNeeded(catalog: catalog) == true)
        #expect(try await context.repositories.store.seedInitialDataIfNeeded(catalog: catalog) == false)

        let workspaces = try await context.repositories.workspaces.fetchAll()
        #expect(workspaces == [catalog.workspace])
        let boards = try await context.repositories.boards.fetchAll(
            workspaceID: catalog.workspace.id,
            includeArchived: true
        )
        #expect(boards.count == catalog.boards.count)
        let templates = try await context.repositories.templates.fetchAll(includeBuiltIn: true)
        #expect(templates.count == catalog.templates.count)

        var actionCount = 0
        for board in boards {
            actionCount += try await context.repositories.actions.fetch(
                boardID: board.id,
                includeDisabled: true
            ).count
        }
        #expect(actionCount == catalog.actions.count)
    }

    @Test("Seeding writes call history so demo screens have records")
    func seedingWritesRecords() async throws {
        let context = CoreDataTestContext()
        _ = try await context.repositories.store.seedInitialDataIfNeeded(catalog: CallDeskSampleData.catalog)

        let records = try await context.repositories.history.fetch(.all)
        #expect(records.count == CallDeskSampleData.records.count)
        #expect(Set(records.map(\.id)) == Set(CallDeskSampleData.records.map(\.id)))
    }

    @Test("Legacy demo audio references are repaired without touching other actions")
    func migrationRepairsOnlyLegacyDemoAudioReferences() async throws {
        let context = CoreDataTestContext()
        let catalog = CallDeskDemoData.makeCatalog(now: .now)
        _ = try await context.repositories.store.seedInitialDataIfNeeded(catalog: catalog)

        var legacyAction = try #require(await context.repositories.actions.action(id: catalog.actions[0].id))
        legacyAction.audioFileName = "001.mp3"
        try await context.repositories.actions.save(legacyAction)

        let userBoardID = try await context.makeBoard(workspaceValue: 90, boardValue: 91)
        let userAction = try CallAction(
            id: coreDataFixedUUID(92),
            boardID: userBoardID,
            title: "001",
            speechText: "",
            playbackMode: .audio,
            audioFileName: "001.mp3"
        )
        try await context.repositories.actions.save(userAction)

        #expect(try await context.repositories.store.migrateLegacyDemoAudioClipReferences() == 1)
        #expect(try await context.repositories.actions.action(id: legacyAction.id)?.audioFileName == "01.mp3")
        #expect(try await context.repositories.actions.action(id: userAction.id)?.audioFileName == "001.mp3")
        #expect(try await context.repositories.store.migrateLegacyDemoAudioClipReferences() == 0)
    }

    @Test("Wrapping keeps repository errors and converts foreign errors to storage failures")
    func errorWrappingMapsToRepositoryError() {
        let repositoryError = RepositoryError.invalidReorder
        #expect(RepositoryError(wrapping: repositoryError) == repositoryError)

        let foreignError = NSError(domain: NSCocoaErrorDomain, code: 133_000)
        let wrapped = RepositoryError(wrapping: foreignError)
        #expect(wrapped == .storageFailure(message: String(describing: foreignError)))
    }

    @Test("Core Data and in-memory repositories order the seeded catalog identically")
    func coreDataMatchesInMemoryOrdering() async throws {
        let catalog = CallDeskSampleData.catalog
        let context = CoreDataTestContext()
        _ = try await context.repositories.store.seedInitialDataIfNeeded(catalog: catalog)
        let inMemory = try InMemoryRepositories.sample()

        let coreDataBoards = try await context.repositories.boards.fetchAll(
            workspaceID: catalog.workspace.id,
            includeArchived: true
        )
        let inMemoryBoards = try await inMemory.boards.fetchAll(
            workspaceID: catalog.workspace.id,
            includeArchived: true
        )
        #expect(coreDataBoards == inMemoryBoards)

        for board in coreDataBoards {
            let coreDataActions = try await context.repositories.actions.fetch(
                boardID: board.id,
                includeDisabled: true
            )
            let inMemoryActions = try await inMemory.actions.fetch(boardID: board.id, includeDisabled: true)
            #expect(coreDataActions == inMemoryActions)
        }

        let coreDataTemplates = try await context.repositories.templates.fetchAll(includeBuiltIn: true)
        let inMemoryTemplates = try await inMemory.templates.fetchAll(includeBuiltIn: true)
        #expect(coreDataTemplates == inMemoryTemplates)
    }
}
