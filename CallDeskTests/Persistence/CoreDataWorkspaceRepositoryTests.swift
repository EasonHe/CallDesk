import Foundation
import Testing
@testable import CallDesk

@Suite("Core Data workspace repository")
struct CoreDataWorkspaceRepositoryTests {
    @Test("Round-trips every field and orders by name then identifier")
    func roundTripsFieldsAndOrders() async throws {
        let context = CoreDataTestContext()
        let repository = context.repositories.workspaces
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let detailed = try Workspace(
            id: coreDataFixedUUID(2),
            name: "Alpha",
            note: "Front desk",
            isArchived: true,
            createdAt: createdAt,
            updatedAt: createdAt.addingTimeInterval(60)
        )
        let sameName = try Workspace(id: coreDataFixedUUID(1), name: "Alpha")
        let last = try Workspace(id: coreDataFixedUUID(3), name: "Zulu")

        try await repository.save(detailed)
        try await repository.save(sameName)
        try await repository.save(last)

        let fetched = try await repository.fetchAll()
        #expect(fetched.map(\.id) == [coreDataFixedUUID(1), coreDataFixedUUID(2), coreDataFixedUUID(3)])
        #expect(try await repository.workspace(id: detailed.id) == detailed)
    }

    @Test("Saving an existing identifier updates the stored workspace")
    func saveUpdatesExistingWorkspace() async throws {
        let context = CoreDataTestContext()
        let repository = context.repositories.workspaces
        let workspaceID = coreDataFixedUUID(4)
        try await repository.save(try Workspace(id: workspaceID, name: "Before"))

        let updated = try Workspace(id: workspaceID, name: "After", note: "Renamed")
        try await repository.save(updated)

        #expect(try await repository.fetchAll().count == 1)
        #expect(try await repository.workspace(id: workspaceID) == updated)
    }

    @Test("Deleting a workspace with boards is rejected")
    func deleteRejectsWorkspaceWithBoards() async throws {
        let context = CoreDataTestContext()
        let workspaceID = coreDataFixedUUID(5)
        let workspace = try Workspace(id: workspaceID, name: "Operations")
        try await context.repositories.workspaces.save(workspace)
        try await context.repositories.boards.save(
            try CallBoard(id: coreDataFixedUUID(6), workspaceID: workspaceID, name: "Lobby", sortOrder: 0)
        )

        await #expect(
            throws: RepositoryError.relationshipConflict(
                message: "Cannot delete a workspace that contains boards."
            )
        ) {
            try await context.repositories.workspaces.delete(id: workspaceID)
        }
        #expect(try await context.repositories.workspaces.workspace(id: workspaceID) == workspace)
    }

    @Test("Deleting an empty workspace succeeds and missing ones are notFound")
    func deleteEmptyWorkspaceAndMissingWorkspace() async throws {
        let context = CoreDataTestContext()
        let repository = context.repositories.workspaces
        let workspaceID = coreDataFixedUUID(7)
        try await repository.save(try Workspace(id: workspaceID, name: "Temporary"))

        try await repository.delete(id: workspaceID)
        #expect(try await repository.workspace(id: workspaceID) == nil)

        await #expect(throws: RepositoryError.notFound(entity: "Workspace", id: workspaceID)) {
            try await repository.delete(id: workspaceID)
        }
    }
}
