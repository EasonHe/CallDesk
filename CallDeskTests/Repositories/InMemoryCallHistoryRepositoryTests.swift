import Foundation
import Testing
@testable import CallDesk

@Suite("Call history repository query values")
struct InMemoryCallHistoryRepositoryTests {
    @Test("History filter rejects an inverted date range and nonpositive limit")
    func historyFilterRejectsInvalidDateRangeAndLimit() {
        let earlier = Date(timeIntervalSinceReferenceDate: 100)
        let later = Date(timeIntervalSinceReferenceDate: 200)

        #expect(throws: RepositoryError.invalidQuery) {
            try CallHistoryFilter(startedFrom: later, startedThrough: earlier)
        }
        #expect(throws: RepositoryError.invalidQuery) {
            try CallHistoryFilter(limit: 0)
        }
    }

    @Test("History filter normalizes a blank search and treats no results as all")
    func historyFilterNormalizesBlankSearchAndEmptyResults() throws {
        let filter = try CallHistoryFilter(searchText: " \n ")

        #expect(filter.searchText == nil)
        #expect(filter.results.isEmpty)
    }

    @Test("Retention policy rejects nonpositive optional limits")
    func retentionPolicyRejectsNonpositiveValues() {
        #expect(throws: RepositoryError.invalidQuery) {
            try HistoryRetentionPolicy(retentionDays: 0)
        }
        #expect(throws: RepositoryError.invalidQuery) {
            try HistoryRetentionPolicy(maximumRecordCount: -1)
        }
    }

    @Test("Saving validates live references but permits updates after deletion")
    func saveValidatesLiveReferencesAndPermitsHistoricalOrphans() async throws {
        let workspaceID = fixedUUID(1)
        let boardID = fixedUUID(2)
        let actionID = fixedUUID(3)
        let recordID = fixedUUID(4)
        let store = try makeStore(workspaceID: workspaceID, boardID: boardID, actionID: actionID)
        let history = InMemoryCallHistoryRepository(store: store)
        let record = try makeRecord(id: recordID, actionID: actionID, boardID: boardID, startedAt: 100)

        await #expect(throws: RepositoryError.relationshipNotFound(entity: "CallAction", id: fixedUUID(5))) {
            try await history.save(try makeRecord(id: fixedUUID(6), actionID: fixedUUID(5), boardID: boardID, startedAt: 101))
        }
        try await history.save(record)

        let actions = InMemoryCallActionRepository(store: store)
        let boards = InMemoryCallBoardRepository(store: store)
        try await actions.delete(id: actionID)
        try await boards.delete(id: boardID)

        try await history.save(record)
        #expect(try await history.record(id: recordID) == record)

        await #expect(throws: RepositoryError.relationshipNotFound(entity: "CallAction", id: fixedUUID(7))) {
            try await history.save(
                try makeRecord(id: recordID, actionID: fixedUUID(7), boardID: boardID, startedAt: 102)
            )
        }
        await #expect(throws: RepositoryError.relationshipNotFound(entity: "CallBoard", id: fixedUUID(8))) {
            try await history.save(
                try makeRecord(id: recordID, actionID: actionID, boardID: fixedUUID(8), startedAt: 102)
            )
        }
        #expect(try await history.record(id: recordID) == record)
    }

    @Test("Fetch filters snapshots case and diacritic insensitively after newest-first sorting")
    func fetchFiltersAndLimitsSortedRecords() async throws {
        let boardID = fixedUUID(10)
        let actionID = fixedUUID(11)
        let olderID = fixedUUID(12)
        let firstTieID = fixedUUID(13)
        let secondTieID = fixedUUID(14)
        let records = [
            try makeRecord(id: olderID, actionID: actionID, boardID: boardID, startedAt: 100, result: .cancelled, title: "Café Queue", speech: "Please call cafe"),
            try makeRecord(id: secondTieID, actionID: actionID, boardID: boardID, startedAt: 200, result: .completed, title: "CAFÉ Queue", speech: "Second"),
            try makeRecord(id: firstTieID, actionID: actionID, boardID: boardID, startedAt: 200, result: .completed, title: "Café Queue", speech: "First")
        ]
        let history = InMemoryCallHistoryRepository(store: try InMemoryCallDeskStore(records: records))

        let filter = try CallHistoryFilter(
            startedFrom: Date(timeIntervalSinceReferenceDate: 100),
            startedThrough: Date(timeIntervalSinceReferenceDate: 200),
            boardID: boardID,
            actionID: actionID,
            results: [.completed],
            searchText: " cafe ",
            limit: 1
        )

        #expect(try await history.fetch(filter).map(\.id) == [firstTieID])
        #expect(try await history.fetch(.all).map(\.id) == [firstTieID, secondTieID, olderID])
    }

    @Test("Bulk deletion ignores absent IDs and delete all removes every record")
    func bulkDeletionAndDeleteAll() async throws {
        let first = try makeRecord(id: fixedUUID(20), startedAt: 100)
        let second = try makeRecord(id: fixedUUID(21), startedAt: 200)
        let history = InMemoryCallHistoryRepository(store: try InMemoryCallDeskStore(records: [first, second]))

        try await history.delete(ids: [first.id, fixedUUID(22)])
        #expect(try await history.fetch(.all) == [second])

        try await history.deleteAll()
        #expect(try await history.fetch(.all).isEmpty)
    }

    @Test("Retention removes expired records before applying the newest count")
    func retentionAppliesDateThenMaximumCount() async throws {
        let expiredID = fixedUUID(30)
        let retainedID = fixedUUID(31)
        let newestID = fixedUUID(32)
        let history = InMemoryCallHistoryRepository(store: try InMemoryCallDeskStore(records: [
            try makeRecord(id: expiredID, startedAt: 2 * 86_400),
            try makeRecord(id: retainedID, startedAt: 4 * 86_400),
            try makeRecord(id: newestID, startedAt: 4.5 * 86_400)
        ]))

        let removed = try await history.enforceRetention(
            try HistoryRetentionPolicy(retentionDays: 2, maximumRecordCount: 1),
            now: Date(timeIntervalSinceReferenceDate: 5 * 86_400)
        )

        #expect(removed == 2)
        #expect(try await history.fetch(.all).map(\.id) == [newestID])
    }

    @Test("Configured history operation failures do not mutate records")
    func configuredFailuresLeaveHistoryUnchanged() async throws {
        let record = try makeRecord(id: fixedUUID(40), startedAt: 100)
        let store = try InMemoryCallDeskStore(records: [record])
        let history = InMemoryCallHistoryRepository(store: store)

        await store.setFailure(true, for: .record)
        await #expect(throws: RepositoryError.configuredFailure(operation: "record")) {
            try await history.record(id: record.id)
        }
        await store.setFailure(false, for: .record)

        await store.setFailure(true, for: .fetchRecords)
        await #expect(throws: RepositoryError.configuredFailure(operation: "fetchRecords")) {
            try await history.fetch(.all)
        }
        await store.setFailure(false, for: .fetchRecords)

        await store.setFailure(true, for: .saveRecord)
        await #expect(throws: RepositoryError.configuredFailure(operation: "saveRecord")) {
            try await history.save(try makeRecord(id: fixedUUID(41), startedAt: 200))
        }
        await store.setFailure(false, for: .saveRecord)

        await store.setFailure(true, for: .deleteRecords)
        await #expect(throws: RepositoryError.configuredFailure(operation: "deleteRecords")) {
            try await history.delete(ids: [record.id])
        }
        await store.setFailure(false, for: .deleteRecords)

        await store.setFailure(true, for: .deleteAllRecords)
        await #expect(throws: RepositoryError.configuredFailure(operation: "deleteAllRecords")) {
            try await history.deleteAll()
        }
        await store.setFailure(false, for: .deleteAllRecords)

        await store.setFailure(true, for: .enforceHistoryRetention)
        await #expect(throws: RepositoryError.configuredFailure(operation: "enforceHistoryRetention")) {
            try await history.enforceRetention(try HistoryRetentionPolicy(maximumRecordCount: 1), now: .now)
        }
        await store.setFailure(false, for: .enforceHistoryRetention)

        #expect(try await history.fetch(.all) == [record])
    }

    @Test("Concurrent history saves retain every distinct record")
    func concurrentSavesRetainEveryDistinctRecord() async throws {
        let history = InMemoryCallHistoryRepository(store: try InMemoryCallDeskStore())
        let records = try (0..<20).map { offset in
            try makeRecord(id: fixedUUID(UInt8(60 + offset)), startedAt: TimeInterval(offset))
        }

        await withTaskGroup(of: Void.self) { group in
            for record in records {
                group.addTask {
                    try? await history.save(record)
                }
            }
        }

        #expect(try await history.fetch(.all).map(\.id).count == records.count)
    }

    @Test("Empty and sample compositions expose six repositories around one store")
    func compositionsShareOneStore() async throws {
        let empty = try InMemoryRepositories.empty()
        #expect(try await empty.workspaces.fetchAll().isEmpty)
        #expect(try await empty.history.fetch(.all).isEmpty)

        let sample = try InMemoryRepositories.sample()
        let action = try #require(await sample.actions.action(id: CallDeskSampleData.actions[0].id))
        #expect(try await sample.boards.board(id: action.boardID) != nil)
        #expect(try await sample.history.fetch(.all).count == CallDeskSampleData.records.count)
    }

    @Test("Composition mutations are visible to related repositories")
    func compositionSharesMutationsAcrossRelatedRepositories() async throws {
        let workspaceID = fixedUUID(90)
        let boardID = fixedUUID(91)
        let actionID = fixedUUID(92)
        let repositories = try InMemoryRepositories.empty()

        try await repositories.workspaces.save(try Workspace(id: workspaceID, name: "Operations"))
        try await repositories.boards.save(
            try CallBoard(id: boardID, workspaceID: workspaceID, name: "Queue", sortOrder: 0)
        )
        try await repositories.actions.save(
            try CallAction(id: actionID, boardID: boardID, title: "A001", speechText: "A001")
        )

        await #expect(
            throws: RepositoryError.relationshipConflict(
                message: "Cannot delete a board that contains actions."
            )
        ) {
            try await repositories.boards.delete(id: boardID)
        }
    }

    private func makeStore(workspaceID: UUID, boardID: UUID, actionID: UUID) throws -> InMemoryCallDeskStore {
        try InMemoryCallDeskStore(
            workspaces: [try Workspace(id: workspaceID, name: "Operations")],
            boards: [try CallBoard(id: boardID, workspaceID: workspaceID, name: "Queue", sortOrder: 0)],
            actions: [try CallAction(id: actionID, boardID: boardID, title: "A001", speechText: "A001")]
        )
    }

    private func makeRecord(
        id: UUID,
        actionID: UUID? = nil,
        boardID: UUID? = nil,
        startedAt: TimeInterval,
        result: CallResult = .completed,
        title: String = "A001",
        speech: String = "Please call A001"
    ) throws -> CallRecord {
        let date = Date(timeIntervalSinceReferenceDate: startedAt)
        return try CallRecord(
            id: id,
            actionID: actionID,
            boardID: boardID,
            actionTitleSnapshot: title,
            spokenTextSnapshot: speech,
            startedAt: date,
            completedAt: date.addingTimeInterval(1),
            result: result
        )
    }

    private func fixedUUID(_ value: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
    }
}
