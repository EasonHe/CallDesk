import Foundation
import Testing
@testable import CallDesk

@Suite("In-memory call board repository")
struct InMemoryCallBoardRepositoryTests {
    @Test("A board cannot change its immutable workspace")
    func saveKeepsBoardInItsWorkspace() async throws {
        let workspaceID = fixedUUID(1)
        let otherWorkspaceID = fixedUUID(2)
        let boardID = fixedUUID(6)
        let original = try CallBoard(id: boardID, workspaceID: workspaceID, name: "Queue", sortOrder: 0)
        let store = try InMemoryCallDeskStore(
            workspaces: [
                try Workspace(id: workspaceID, name: "One"),
                try Workspace(id: otherWorkspaceID, name: "Two")
            ],
            boards: [original]
        )
        let repository = InMemoryCallBoardRepository(store: store)

        let renamed = try CallBoard(id: boardID, workspaceID: workspaceID, name: "Front Desk", sortOrder: 0)
        try await repository.save(renamed)
        #expect(try await repository.board(id: boardID) == renamed)

        await #expect(
            throws: RepositoryError.relationshipConflict(
                message: "Board workspace cannot be changed."
            )
        ) {
            try await repository.save(
                try CallBoard(id: boardID, workspaceID: otherWorkspaceID, name: "Queue", sortOrder: 0)
            )
        }
    }

    @Test("Fetch excludes archived boards unless requested")
    func fetchFiltersArchives() async throws {
        let workspaceID = fixedUUID(7)
        let store = try InMemoryCallDeskStore(
            workspaces: [try Workspace(id: workspaceID, name: "Operations")],
            boards: [
                try CallBoard(id: fixedUUID(9), workspaceID: workspaceID, name: "Second", sortOrder: 1),
                try CallBoard(id: fixedUUID(10), workspaceID: workspaceID, name: "First", sortOrder: 0),
                try CallBoard(id: fixedUUID(11), workspaceID: workspaceID, name: "Archived", sortOrder: 2, isArchived: true)
            ]
        )
        let repository = InMemoryCallBoardRepository(store: store)

        #expect(try await repository.fetchAll(workspaceID: workspaceID, includeArchived: false).map(\.id) == [fixedUUID(10), fixedUUID(9)])
        #expect(try await repository.fetchAll(workspaceID: workspaceID, includeArchived: true).map(\.id) == [fixedUUID(10), fixedUUID(9), fixedUUID(11)])
    }

    @Test("Deleting a board with actions and an invalid reorder preserve stored boards")
    func deleteProtectionAndAtomicReorder() async throws {
        let workspaceID = fixedUUID(12)
        let boardID = fixedUUID(13)
        let secondBoardID = fixedUUID(14)
        let board = try CallBoard(id: boardID, workspaceID: workspaceID, name: "One", sortOrder: 0)
        let secondBoard = try CallBoard(id: secondBoardID, workspaceID: workspaceID, name: "Two", sortOrder: 1)
        let store = try InMemoryCallDeskStore(
            workspaces: [try Workspace(id: workspaceID, name: "Operations")],
            boards: [board, secondBoard],
            actions: [try CallAction(id: fixedUUID(15), boardID: boardID, title: "A001", speechText: "A001")]
        )
        let repository = InMemoryCallBoardRepository(store: store)
        let before = try await repository.fetchAll(workspaceID: workspaceID, includeArchived: true)

        await #expect(
            throws: RepositoryError.relationshipConflict(
                message: "Cannot delete a board that contains actions."
            )
        ) {
            try await repository.delete(id: boardID)
        }
        await #expect(throws: RepositoryError.invalidReorder) {
            try await repository.reorder(workspaceID: workspaceID, orderedIDs: [boardID])
        }
        #expect(try await repository.fetchAll(workspaceID: workspaceID, includeArchived: true) == before)
    }

    @Test("Reorder rejects a missing workspace before accepting an empty list")
    func reorderRejectsMissingWorkspace() async throws {
        let repository = InMemoryCallBoardRepository(store: try InMemoryCallDeskStore())
        let missingWorkspaceID = fixedUUID(16)

        await #expect(throws: RepositoryError.relationshipNotFound(entity: "Workspace", id: missingWorkspaceID)) {
            try await repository.reorder(workspaceID: missingWorkspaceID, orderedIDs: [])
        }
    }

    @Test("Deleting a board leaves its historical call record intact")
    func deleteLeavesHistoryIntact() async throws {
        let workspaceID = fixedUUID(17)
        let boardID = fixedUUID(18)
        let recordID = fixedUUID(19)
        let board = try CallBoard(id: boardID, workspaceID: workspaceID, name: "Queue", sortOrder: 0)
        let record = try CallRecord(
            id: recordID,
            actionID: fixedUUID(20),
            boardID: boardID,
            actionTitleSnapshot: "A001",
            spokenTextSnapshot: "A001",
            startedAt: Date(timeIntervalSinceReferenceDate: 100),
            completedAt: Date(timeIntervalSinceReferenceDate: 101),
            result: .completed
        )
        let store = try InMemoryCallDeskStore(
            workspaces: [try Workspace(id: workspaceID, name: "Operations")],
            boards: [board],
            records: [record]
        )
        let repository = InMemoryCallBoardRepository(store: store)

        try await repository.delete(id: boardID)
        #expect(try await repository.board(id: boardID) == nil)
        #expect(try await store.record(id: recordID) == record)
    }

    @Test("Configured board read write and reorder failures leave data unchanged")
    func configuredFailuresLeaveBoardsUnchanged() async throws {
        let workspaceID = fixedUUID(21)
        let board = try CallBoard(id: fixedUUID(22), workspaceID: workspaceID, name: "Queue", sortOrder: 0)
        let store = try InMemoryCallDeskStore(
            workspaces: [try Workspace(id: workspaceID, name: "Operations")],
            boards: [board]
        )
        let repository = InMemoryCallBoardRepository(store: store)

        await store.setFailure(true, for: .fetchAllBoards)
        await #expect(throws: RepositoryError.configuredFailure(operation: "fetchAllBoards")) {
            try await repository.fetchAll(workspaceID: workspaceID, includeArchived: true)
        }
        await store.setFailure(false, for: .fetchAllBoards)

        await store.setFailure(true, for: .saveBoard)
        await #expect(throws: RepositoryError.configuredFailure(operation: "saveBoard")) {
            try await repository.save(try CallBoard(id: fixedUUID(23), workspaceID: workspaceID, name: "New", sortOrder: 1))
        }
        await store.setFailure(false, for: .saveBoard)

        await store.setFailure(true, for: .reorderBoards)
        await #expect(throws: RepositoryError.configuredFailure(operation: "reorderBoards")) {
            try await repository.reorder(workspaceID: workspaceID, orderedIDs: [board.id])
        }
        await store.setFailure(false, for: .reorderBoards)

        #expect(try await repository.fetchAll(workspaceID: workspaceID, includeArchived: true) == [board])
    }

    private func fixedUUID(_ value: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
    }
}
