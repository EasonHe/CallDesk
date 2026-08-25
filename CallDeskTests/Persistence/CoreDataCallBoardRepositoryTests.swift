import Foundation
import Testing
@testable import CallDesk

@Suite("Core Data call board repository")
struct CoreDataCallBoardRepositoryTests {
    @Test("Fetch orders boards and filters archived boards")
    func fetchOrdersAndFiltersArchived() async throws {
        let context = CoreDataTestContext()
        let workspaceID = coreDataFixedUUID(1)
        try await context.repositories.workspaces.save(try Workspace(id: workspaceID, name: "Hall"))
        let boards = context.repositories.boards
        let firstBoardID = coreDataFixedUUID(3)
        let secondBoardID = coreDataFixedUUID(4)
        let archivedBoardID = coreDataFixedUUID(5)
        try await boards.save(
            try CallBoard(id: firstBoardID, workspaceID: workspaceID, name: "Queue", sortOrder: 0)
        )
        try await boards.save(
            try CallBoard(id: secondBoardID, workspaceID: workspaceID, name: "Loose", sortOrder: 1)
        )
        try await boards.save(
            try CallBoard(
                id: archivedBoardID,
                workspaceID: workspaceID,
                name: "Archived",
                sortOrder: 2,
                isArchived: true
            )
        )

        let everything = try await boards.fetchAll(workspaceID: workspaceID, includeArchived: true)
        #expect(everything.map(\.id) == [firstBoardID, secondBoardID, archivedBoardID])

        let active = try await boards.fetchAll(workspaceID: workspaceID, includeArchived: false)
        #expect(active.map(\.id) == [firstBoardID, secondBoardID])
    }

    @Test("Save validates workspace existence and the fixed workspace")
    func saveValidatesRelationships() async throws {
        let context = CoreDataTestContext()
        let workspaceID = coreDataFixedUUID(6)
        let otherWorkspaceID = coreDataFixedUUID(7)
        let boardID = coreDataFixedUUID(9)
        let boards = context.repositories.boards

        await #expect(throws: RepositoryError.relationshipNotFound(entity: "Workspace", id: workspaceID)) {
            try await boards.save(
                try CallBoard(id: boardID, workspaceID: workspaceID, name: "Queue", sortOrder: 0)
            )
        }

        try await context.repositories.workspaces.save(try Workspace(id: workspaceID, name: "Main"))
        try await context.repositories.workspaces.save(try Workspace(id: otherWorkspaceID, name: "Other"))

        try await boards.save(try CallBoard(id: boardID, workspaceID: workspaceID, name: "Queue", sortOrder: 0))
        await #expect(
            throws: RepositoryError.relationshipConflict(message: "Board workspace cannot be changed.")
        ) {
            try await boards.save(
                try CallBoard(id: boardID, workspaceID: otherWorkspaceID, name: "Queue", sortOrder: 0)
            )
        }
    }

    @Test("Delete protects boards that still contain actions")
    func deleteProtectsBoardsWithActions() async throws {
        let context = CoreDataTestContext()
        let workspaceID = coreDataFixedUUID(11)
        let boardID = coreDataFixedUUID(12)
        try await context.repositories.workspaces.save(try Workspace(id: workspaceID, name: "Hall"))
        try await context.repositories.boards.save(
            try CallBoard(id: boardID, workspaceID: workspaceID, name: "Queue", sortOrder: 0)
        )
        try await context.repositories.actions.save(
            try CallAction(id: coreDataFixedUUID(13), boardID: boardID, title: "A001", speechText: "Number A001")
        )

        await #expect(
            throws: RepositoryError.relationshipConflict(message: "Cannot delete a board that contains actions.")
        ) {
            try await context.repositories.boards.delete(id: boardID)
        }

        try await context.repositories.actions.delete(id: coreDataFixedUUID(13))
        try await context.repositories.boards.delete(id: boardID)
        #expect(try await context.repositories.boards.board(id: boardID) == nil)
    }

    @Test("Reorder is scoped to one workspace and fails atomically")
    func reorderScopedToWorkspaceFailsAtomically() async throws {
        let context = CoreDataTestContext()
        let workspaceID = coreDataFixedUUID(14)
        let otherWorkspaceID = coreDataFixedUUID(15)
        try await context.repositories.workspaces.save(try Workspace(id: workspaceID, name: "Hall"))
        try await context.repositories.workspaces.save(try Workspace(id: otherWorkspaceID, name: "Annex"))
        let boards = context.repositories.boards
        let firstID = coreDataFixedUUID(16)
        let secondID = coreDataFixedUUID(17)
        let foreignID = coreDataFixedUUID(18)
        try await boards.save(
            try CallBoard(id: firstID, workspaceID: workspaceID, name: "One", sortOrder: 0)
        )
        try await boards.save(
            try CallBoard(id: secondID, workspaceID: workspaceID, name: "Two", sortOrder: 1)
        )
        try await boards.save(try CallBoard(id: foreignID, workspaceID: otherWorkspaceID, name: "Foreign", sortOrder: 0))

        try await boards.reorder(workspaceID: workspaceID, orderedIDs: [secondID, firstID])
        let reordered = try await boards.fetchAll(workspaceID: workspaceID, includeArchived: true)
        #expect(reordered.map(\.id) == [secondID, firstID])

        await #expect(throws: RepositoryError.invalidReorder) {
            try await boards.reorder(
                workspaceID: workspaceID,
                orderedIDs: [firstID, secondID, foreignID]
            )
        }

        let unchanged = try await boards.fetchAll(workspaceID: workspaceID, includeArchived: true)
        #expect(unchanged.map(\.id) == [secondID, firstID])
    }
}
