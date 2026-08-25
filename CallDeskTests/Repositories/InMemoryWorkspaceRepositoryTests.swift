import Foundation
import Testing
@testable import CallDesk

@Suite("In-memory workspace repository")
struct InMemoryWorkspaceRepositoryTests {
    @Test("Fetch orders workspaces by name then identifier and saves updates")
    func fetchOrdersAndSaveUpdates() async throws {
        let secondID = fixedUUID(2)
        let firstID = fixedUUID(1)
        let store = try InMemoryCallDeskStore(
            workspaces: [
                try Workspace(id: secondID, name: "Alpha"),
                try Workspace(id: firstID, name: "Alpha"),
                try Workspace(id: fixedUUID(3), name: "Zulu")
            ]
        )
        let repository = InMemoryWorkspaceRepository(store: store)

        #expect(try await repository.fetchAll().map(\.id) == [firstID, secondID, fixedUUID(3)])

        let updated = try Workspace(id: firstID, name: "Bravo")
        try await repository.save(updated)
        #expect(try await repository.workspace(id: firstID) == updated)
    }

    @Test("Deleting a workspace with boards is rejected")
    func deleteRejectsWorkspaceWithBoards() async throws {
        let workspaceID = fixedUUID(4)
        let workspace = try Workspace(id: workspaceID, name: "Operations")
        let board = try CallBoard(id: fixedUUID(5), workspaceID: workspaceID, name: "Lobby", sortOrder: 0)
        let store = try InMemoryCallDeskStore(workspaces: [workspace], boards: [board])
        let repository = InMemoryWorkspaceRepository(store: store)

        await #expect(
            throws: RepositoryError.relationshipConflict(
                message: "Cannot delete a workspace that contains boards."
            )
        ) {
            try await repository.delete(id: workspaceID)
        }
        #expect(try await repository.workspace(id: workspaceID) == workspace)
    }

    @Test("Configured read and write failures leave workspaces unchanged")
    func configuredReadAndWriteFailuresLeaveWorkspacesUnchanged() async throws {
        let workspaceID = fixedUUID(6)
        let existing = try Workspace(id: workspaceID, name: "Existing")
        let store = try InMemoryCallDeskStore(workspaces: [existing])
        let repository = InMemoryWorkspaceRepository(store: store)

        await store.setFailure(true, for: .fetchWorkspaces)
        await #expect(throws: RepositoryError.configuredFailure(operation: "fetchWorkspaces")) {
            try await repository.fetchAll()
        }
        await store.setFailure(false, for: .fetchWorkspaces)

        await store.setFailure(true, for: .saveWorkspace)
        await #expect(throws: RepositoryError.configuredFailure(operation: "saveWorkspace")) {
            try await repository.save(try Workspace(id: fixedUUID(7), name: "New"))
        }
        await store.setFailure(false, for: .saveWorkspace)

        #expect(try await repository.fetchAll() == [existing])
    }

    @Test("Delete completes workspace CRUD when it has no boards")
    func deleteWorkspaceWithoutBoards() async throws {
        let workspaceID = fixedUUID(8)
        let workspace = try Workspace(id: workspaceID, name: "Temporary")
        let repository = InMemoryWorkspaceRepository(
            store: try InMemoryCallDeskStore(workspaces: [workspace])
        )

        try await repository.delete(id: workspaceID)
        #expect(try await repository.workspace(id: workspaceID) == nil)
    }

    private func fixedUUID(_ value: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
    }
}
