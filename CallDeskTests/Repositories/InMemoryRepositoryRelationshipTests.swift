import Foundation
import Testing
@testable import CallDesk

@Suite("In-memory repository store relationships")
struct InMemoryRepositoryRelationshipTests {
    @Test("Store rejects duplicate identifiers")
    func storeRejectsDuplicateIdentifiers() throws {
        let workspaceID = fixedUUID(1)
        let workspace = try Workspace(id: workspaceID, name: "Operations")

        #expect(
            throws: RepositoryError.duplicateIdentifier(entity: "Workspace", id: workspaceID)
        ) {
            try InMemoryCallDeskStore(workspaces: [workspace, workspace])
        }
    }

    @Test("Store rejects a board whose workspace is absent")
    func storeRejectsBoardWithMissingWorkspace() throws {
        let missingWorkspaceID = fixedUUID(2)
        let board = try CallBoard(
            id: fixedUUID(7),
            workspaceID: missingWorkspaceID,
            name: "Queue",
            sortOrder: 0
        )

        #expect(
            throws: RepositoryError.relationshipNotFound(entity: "Workspace", id: missingWorkspaceID)
        ) {
            try InMemoryCallDeskStore(boards: [board])
        }
    }

    @Test("Store rejects an action whose board is absent")
    func storeRejectsActionWithMissingBoard() throws {
        let missingBoardID = fixedUUID(11)
        let action = try CallAction(
            id: fixedUUID(12),
            boardID: missingBoardID,
            title: "A021",
            speechText: "Please A021 proceed to Counter 1."
        )

        #expect(
            throws: RepositoryError.relationshipNotFound(entity: "CallBoard", id: missingBoardID)
        ) {
            try InMemoryCallDeskStore(actions: [action])
        }
    }

    @Test("Store accepts historical records whose references no longer exist")
    func storeAcceptsHistoricalOrphanReferences() throws {
        let record = try CallRecord(
            id: fixedUUID(8),
            actionID: fixedUUID(9),
            boardID: fixedUUID(10),
            actionTitleSnapshot: "A021",
            spokenTextSnapshot: "Please A021 proceed to Counter 1.",
            startedAt: Date(timeIntervalSinceReferenceDate: 100),
            completedAt: Date(timeIntervalSinceReferenceDate: 101),
            result: .completed
        )

        _ = try InMemoryCallDeskStore(records: [record])
    }

    @Test("Configured failures are typed by operation")
    func configuredFailureIsReportedForItsOperation() async throws {
        let store = try InMemoryCallDeskStore()

        await store.setFailure(true, for: .fetchWorkspaces)

        await #expect(
            throws: RepositoryError.configuredFailure(operation: "fetchWorkspaces")
        ) {
            try await store.checkFailure(for: .fetchWorkspaces)
        }
    }

    private func fixedUUID(_ value: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
    }
}
