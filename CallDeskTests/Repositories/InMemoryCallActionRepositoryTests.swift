import Foundation
import Testing
@testable import CallDesk

@Suite("In-memory call action repository")
struct InMemoryCallActionRepositoryTests {
    @Test("Saving requires a live board and preserves action board ownership")
    func saveRequiresBoardAndPreservesOwnership() async throws {
        let workspaceID = fixedUUID(1)
        let boardID = fixedUUID(2)
        let otherBoardID = fixedUUID(3)
        let actionID = fixedUUID(4)
        let original = try CallAction(id: actionID, boardID: boardID, title: "A001", speechText: "A001")
        let store = try InMemoryCallDeskStore(
            workspaces: [try Workspace(id: workspaceID, name: "Operations")],
            boards: [
                try CallBoard(id: boardID, workspaceID: workspaceID, name: "One", sortOrder: 0),
                try CallBoard(id: otherBoardID, workspaceID: workspaceID, name: "Two", sortOrder: 1)
            ],
            actions: [original]
        )
        let repository = InMemoryCallActionRepository(store: store)

        await #expect(throws: RepositoryError.relationshipNotFound(entity: "CallBoard", id: fixedUUID(5))) {
            try await repository.save(try CallAction(id: fixedUUID(6), boardID: fixedUUID(5), title: "Missing", speechText: "Missing"))
        }
        await #expect(
            throws: RepositoryError.relationshipConflict(
                message: "Action board cannot be changed."
            )
        ) {
            try await repository.save(try CallAction(id: actionID, boardID: otherBoardID, title: "Moved", speechText: "Moved"))
        }
        #expect(try await repository.action(id: actionID) == original)
    }

    @Test("Fetch filters disabled actions and reorder requires the exact board action set")
    func fetchFiltersAndReordersExactActionSet() async throws {
        let workspaceID = fixedUUID(7)
        let boardID = fixedUUID(8)
        let firstID = fixedUUID(9)
        let secondID = fixedUUID(10)
        let store = try InMemoryCallDeskStore(
            workspaces: [try Workspace(id: workspaceID, name: "Operations")],
            boards: [try CallBoard(id: boardID, workspaceID: workspaceID, name: "Queue", sortOrder: 0)],
            actions: [
                try CallAction(id: firstID, boardID: boardID, title: "A001", speechText: "A001", sortOrder: 0),
                try CallAction(id: secondID, boardID: boardID, title: "A002", speechText: "A002", sortOrder: 1),
                try CallAction(id: fixedUUID(11), boardID: boardID, title: "Disabled", speechText: "Disabled", sortOrder: 2, isEnabled: false)
            ]
        )
        let repository = InMemoryCallActionRepository(store: store)

        #expect(try await repository.fetch(boardID: boardID, includeDisabled: false).map(\.id) == [firstID, secondID])
        let before = try await repository.fetch(boardID: boardID, includeDisabled: true)
        await #expect(throws: RepositoryError.invalidReorder) {
            try await repository.reorder(boardID: boardID, orderedIDs: [secondID, firstID])
        }
        #expect(try await repository.fetch(boardID: boardID, includeDisabled: true) == before)

        try await repository.reorder(boardID: boardID, orderedIDs: [secondID, firstID, fixedUUID(11)])
        #expect(try await repository.fetch(boardID: boardID, includeDisabled: true).map(\.id) == [secondID, firstID, fixedUUID(11)])
    }

    @Test("Deleting an action does not remove historical records")
    func deleteDoesNotRewriteHistory() async throws {
        let workspaceID = fixedUUID(12)
        let boardID = fixedUUID(13)
        let actionID = fixedUUID(14)
        let recordID = fixedUUID(15)
        let record = try CallRecord(
            id: recordID,
            actionID: actionID,
            boardID: boardID,
            actionTitleSnapshot: "A001",
            spokenTextSnapshot: "A001",
            startedAt: Date(timeIntervalSinceReferenceDate: 100),
            completedAt: Date(timeIntervalSinceReferenceDate: 101),
            result: .completed
        )
        let store = try InMemoryCallDeskStore(
            workspaces: [try Workspace(id: workspaceID, name: "Operations")],
            boards: [try CallBoard(id: boardID, workspaceID: workspaceID, name: "Queue", sortOrder: 0)],
            actions: [try CallAction(id: actionID, boardID: boardID, title: "A001", speechText: "A001")],
            records: [record]
        )
        let actionRepository = InMemoryCallActionRepository(store: store)

        try await actionRepository.delete(id: actionID)
        #expect(try await store.record(id: recordID) == record)
    }

    @Test("Reorder rejects a missing board before accepting an empty action set")
    func reorderRejectsMissingBoard() async throws {
        let repository = InMemoryCallActionRepository(store: try InMemoryCallDeskStore())
        let missingBoardID = fixedUUID(16)

        await #expect(throws: RepositoryError.relationshipNotFound(entity: "CallBoard", id: missingBoardID)) {
            try await repository.reorder(boardID: missingBoardID, orderedIDs: [])
        }
    }

    @Test("Save lookup and delete complete action CRUD")
    func saveLookupAndDeleteAction() async throws {
        let workspaceID = fixedUUID(17)
        let boardID = fixedUUID(18)
        let actionID = fixedUUID(19)
        let action = try CallAction(id: actionID, boardID: boardID, title: "A003", speechText: "A003")
        let repository = InMemoryCallActionRepository(
            store: try InMemoryCallDeskStore(
                workspaces: [try Workspace(id: workspaceID, name: "Operations")],
                boards: [try CallBoard(id: boardID, workspaceID: workspaceID, name: "Queue", sortOrder: 0)]
            )
        )

        try await repository.save(action)
        #expect(try await repository.action(id: actionID) == action)
        try await repository.delete(id: actionID)
        #expect(try await repository.action(id: actionID) == nil)
    }

    @Test("Configured action read write and reorder failures leave data unchanged")
    func configuredFailuresLeaveActionsUnchanged() async throws {
        let workspaceID = fixedUUID(20)
        let boardID = fixedUUID(21)
        let action = try CallAction(id: fixedUUID(22), boardID: boardID, title: "A001", speechText: "A001")
        let store = try InMemoryCallDeskStore(
            workspaces: [try Workspace(id: workspaceID, name: "Operations")],
            boards: [try CallBoard(id: boardID, workspaceID: workspaceID, name: "Queue", sortOrder: 0)],
            actions: [action]
        )
        let repository = InMemoryCallActionRepository(store: store)

        await store.setFailure(true, for: .fetchActions)
        await #expect(throws: RepositoryError.configuredFailure(operation: "fetchActions")) {
            try await repository.fetch(boardID: boardID, includeDisabled: true)
        }
        await store.setFailure(false, for: .fetchActions)

        await store.setFailure(true, for: .saveAction)
        await #expect(throws: RepositoryError.configuredFailure(operation: "saveAction")) {
            try await repository.save(try CallAction(id: fixedUUID(23), boardID: boardID, title: "A002", speechText: "A002"))
        }
        await store.setFailure(false, for: .saveAction)

        await store.setFailure(true, for: .reorderActions)
        await #expect(throws: RepositoryError.configuredFailure(operation: "reorderActions")) {
            try await repository.reorder(boardID: boardID, orderedIDs: [action.id])
        }
        await store.setFailure(false, for: .reorderActions)

        #expect(try await repository.fetch(boardID: boardID, includeDisabled: true) == [action])
    }

    @Test("Concurrent saves retain every distinct action in deterministic sort order")
    func concurrentSavesRetainDistinctActionsInSortOrder() async throws {
        let workspaceID = fixedUUID(24)
        let boardID = fixedUUID(25)
        let first = try CallAction(id: fixedUUID(26), boardID: boardID, title: "A001", speechText: "A001", sortOrder: 2)
        let second = try CallAction(id: fixedUUID(27), boardID: boardID, title: "A002", speechText: "A002", sortOrder: 0)
        let third = try CallAction(id: fixedUUID(28), boardID: boardID, title: "A003", speechText: "A003", sortOrder: 1)
        let repository = InMemoryCallActionRepository(
            store: try InMemoryCallDeskStore(
                workspaces: [try Workspace(id: workspaceID, name: "Operations")],
                boards: [try CallBoard(id: boardID, workspaceID: workspaceID, name: "Queue", sortOrder: 0)]
            )
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            for action in [first, second, third] {
                group.addTask {
                    try await repository.save(action)
                }
            }
            try await group.waitForAll()
        }

        let savedActions = try await repository.fetch(boardID: boardID, includeDisabled: true)
        #expect(savedActions.count == 3)
        #expect(savedActions.map(\.id) == [second.id, third.id, first.id])
    }

    private func fixedUUID(_ value: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
    }
}
