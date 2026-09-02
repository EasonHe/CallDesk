import CoreData
import Foundation
import Testing
@testable import CallDesk

@Suite("Core Data call history repository")
struct CoreDataCallHistoryRepositoryTests {
    @Test("Round-trips every field including enums and optional values")
    func roundTripsEveryField() async throws {
        let context = CoreDataTestContext()
        let history = context.repositories.history
        let startedAt = Date(timeIntervalSinceReferenceDate: 500)
        let record = try CallRecord(
            id: coreDataFixedUUID(1),
            actionTitleSnapshot: "A001",
            spokenTextSnapshot: "Number A001 to window 3",
            startedAt: startedAt,
            completedAt: startedAt.addingTimeInterval(2),
            result: .failed,
            repeatIndex: 2,
            audioRouteName: "Speaker",
            errorDescription: "Synthesizer unavailable"
        )
        let minimal = try CallRecord(
            id: coreDataFixedUUID(2),
            actionTitleSnapshot: "A002",
            spokenTextSnapshot: "Number A002",
            startedAt: startedAt.addingTimeInterval(10)
        )

        try await history.save(record)
        try await history.save(minimal)

        #expect(try await history.record(id: record.id) == record)
        #expect(try await history.record(id: minimal.id) == minimal)
    }

    @Test("Saving validates live references but keeps orphaned snapshots")
    func saveValidatesLiveReferencesAndKeepsOrphans() async throws {
        let context = CoreDataTestContext()
        let history = context.repositories.history
        let boardID = try await context.makeBoard(workspaceValue: 3, boardValue: 4)
        let actionID = coreDataFixedUUID(5)
        try await context.repositories.actions.save(
            try CallAction(id: actionID, boardID: boardID, title: "A001", speechText: "A001")
        )
        let recordID = coreDataFixedUUID(6)
        let record = try makeRecord(id: recordID, actionID: actionID, boardID: boardID, startedAt: 100)

        await #expect(throws: RepositoryError.relationshipNotFound(entity: "CallAction", id: coreDataFixedUUID(7))) {
            try await history.save(
                try self.makeRecord(id: coreDataFixedUUID(8), actionID: coreDataFixedUUID(7), boardID: boardID, startedAt: 101)
            )
        }
        try await history.save(record)

        try await context.repositories.actions.delete(id: actionID)
        try await context.repositories.boards.delete(id: boardID)

        try await history.save(record)
        #expect(try await history.record(id: recordID) == record)

        await #expect(throws: RepositoryError.relationshipNotFound(entity: "CallAction", id: coreDataFixedUUID(9))) {
            try await history.save(
                try self.makeRecord(id: recordID, actionID: coreDataFixedUUID(9), boardID: boardID, startedAt: 102)
            )
        }
        await #expect(throws: RepositoryError.relationshipNotFound(entity: "CallBoard", id: coreDataFixedUUID(10))) {
            try await history.save(
                try self.makeRecord(id: recordID, actionID: actionID, boardID: coreDataFixedUUID(10), startedAt: 102)
            )
        }
        #expect(try await history.record(id: recordID) == record)
    }

    @Test("Fetch filters snapshots case and diacritic insensitively after newest-first sorting")
    func fetchFiltersAndLimitsSortedRecords() async throws {
        let context = CoreDataTestContext()
        let history = context.repositories.history
        let boardID = try await context.makeBoard(workspaceValue: 11, boardValue: 12)
        let actionID = coreDataFixedUUID(13)
        try await context.repositories.actions.save(
            try CallAction(id: actionID, boardID: boardID, title: "A001", speechText: "A001")
        )
        let olderID = coreDataFixedUUID(14)
        let firstTieID = coreDataFixedUUID(15)
        let secondTieID = coreDataFixedUUID(16)
        try await history.save(
            try makeRecord(
                id: olderID,
                actionID: actionID,
                boardID: boardID,
                startedAt: 100,
                result: .cancelled,
                title: "Café Queue",
                speech: "Please call cafe"
            )
        )
        try await history.save(
            try makeRecord(
                id: secondTieID,
                actionID: actionID,
                boardID: boardID,
                startedAt: 200,
                result: .completed,
                title: "CAFÉ Queue",
                speech: "Second"
            )
        )
        try await history.save(
            try makeRecord(
                id: firstTieID,
                actionID: actionID,
                boardID: boardID,
                startedAt: 200,
                result: .completed,
                title: "Café Queue",
                speech: "First"
            )
        )

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

    @Test("A limited fetch does not materialize records beyond its result window")
    func limitedFetchDoesNotMaterializeOlderRecords() async throws {
        let context = CoreDataTestContext()
        let history = context.repositories.history
        let newest = try makeRecord(id: coreDataFixedUUID(30), startedAt: 200)
        try await history.save(newest)

        try await context.persistence.container.viewContext.perform {
            let invalidOlderRecord = CDCallRecord(context: context.persistence.container.viewContext)
            invalidOlderRecord.apply(try self.makeRecord(id: coreDataFixedUUID(31), startedAt: 100))
            invalidOlderRecord.repeatIndex = -1
            try context.persistence.container.viewContext.save()
        }

        let latestOnly = try CallHistoryFilter(results: [.completed], limit: 1)

        #expect(try await history.fetch(latestOnly) == [newest])
    }

    @Test("Bulk deletion ignores absent IDs and delete all removes every record")
    func bulkDeletionAndDeleteAll() async throws {
        let context = CoreDataTestContext()
        let history = context.repositories.history
        let first = try makeRecord(id: coreDataFixedUUID(17), startedAt: 100)
        let second = try makeRecord(id: coreDataFixedUUID(18), startedAt: 200)
        try await history.save(first)
        try await history.save(second)

        try await history.delete(ids: [first.id, coreDataFixedUUID(19)])
        #expect(try await history.fetch(.all) == [second])

        try await history.deleteAll()
        #expect(try await history.fetch(.all).isEmpty)
    }

    @Test("Retention removes expired records before applying the newest count")
    func retentionAppliesDateThenMaximumCount() async throws {
        let context = CoreDataTestContext()
        let history = context.repositories.history
        let expiredID = coreDataFixedUUID(20)
        let retainedID = coreDataFixedUUID(21)
        let newestID = coreDataFixedUUID(22)
        try await history.save(try makeRecord(id: expiredID, startedAt: 2 * 86_400))
        try await history.save(try makeRecord(id: retainedID, startedAt: 4 * 86_400))
        try await history.save(try makeRecord(id: newestID, startedAt: 4.5 * 86_400))

        let removed = try await history.enforceRetention(
            try HistoryRetentionPolicy(retentionDays: 2, maximumRecordCount: 1),
            now: Date(timeIntervalSinceReferenceDate: 5 * 86_400)
        )

        #expect(removed == 2)
        #expect(try await history.fetch(.all).map(\.id) == [newestID])
    }

    @Test("Retention deletes records without materializing their domain values")
    func retentionDoesNotMaterializeRecords() async throws {
        let context = CoreDataTestContext()
        let history = context.repositories.history
        let newest = try makeRecord(id: coreDataFixedUUID(32), startedAt: 200)
        try await history.save(newest)

        try await context.persistence.container.viewContext.perform {
            let invalidOlderRecord = CDCallRecord(context: context.persistence.container.viewContext)
            invalidOlderRecord.apply(try self.makeRecord(id: coreDataFixedUUID(33), startedAt: 100))
            invalidOlderRecord.repeatIndex = -1
            try context.persistence.container.viewContext.save()
        }

        let removed = try await history.enforceRetention(
            try HistoryRetentionPolicy(maximumRecordCount: 1),
            now: Date(timeIntervalSinceReferenceDate: 300)
        )

        #expect(removed == 1)
        #expect(try await history.fetch(.all) == [newest])
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
}
