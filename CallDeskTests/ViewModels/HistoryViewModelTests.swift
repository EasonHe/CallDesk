import Foundation
import Testing
@testable import CallDesk

@MainActor
@Suite("History view model")
struct HistoryViewModelTests {
    @Test("Loading returns records sorted by most recent start time")
    func loadReturnsRecordsSortedByMostRecentStart() async throws {
        let fixture = try makeFixture()

        await fixture.viewModel.load()

        guard case .loaded(let records) = fixture.viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        #expect(records.map(\.actionTitleSnapshot) == ["Pause", "B002", "A001"])
    }

    @Test("Search narrows records to matching snapshots")
    func searchNarrowsRecordsToMatchingSnapshots() async throws {
        let fixture = try makeFixture()
        fixture.viewModel.searchText = "a001"

        await fixture.viewModel.load()

        guard case .loaded(let records) = fixture.viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        #expect(records.map(\.actionTitleSnapshot) == ["A001"])
    }

    @Test("Result filtering keeps only records with the selected result")
    func resultFilteringKeepsOnlySelectedResult() async throws {
        let fixture = try makeFixture()
        fixture.viewModel.selectedResult = .failed

        await fixture.viewModel.load()

        guard case .loaded(let records) = fixture.viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        #expect(records.map(\.actionTitleSnapshot) == ["B002"])
        #expect(fixture.viewModel.hasActiveFilters)
    }

    @Test("Today keeps only records that started on the current day")
    func todayKeepsOnlyRecordsFromCurrentDay() async throws {
        let fixture = try makeTimeRangeFixture()
        fixture.viewModel.selectedTimeRange = .today

        await fixture.viewModel.load()

        guard case .loaded(let records) = fixture.viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        #expect(records.map(\.actionTitleSnapshot) == ["Fresh"])
        #expect(fixture.viewModel.hasActiveFilters)
    }

    @Test("Last seven days keeps records inside the rolling window")
    func lastSevenDaysKeepsRecordsInsideWindow() async throws {
        let fixture = try makeTimeRangeFixture()
        fixture.viewModel.selectedTimeRange = .lastSevenDays

        await fixture.viewModel.load()

        guard case .loaded(let records) = fixture.viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        #expect(records.map(\.actionTitleSnapshot) == ["Fresh", "Recent"])
    }

    @Test("Clearing filters restores the full record list")
    func clearingFiltersRestoresFullList() async throws {
        let fixture = try makeFixture()
        fixture.viewModel.searchText = "A001"
        fixture.viewModel.selectedResult = .failed
        fixture.viewModel.selectedTimeRange = .lastSevenDays
        await fixture.viewModel.load()
        #expect(fixture.viewModel.state == .empty)

        fixture.viewModel.clearFilters()
        await fixture.viewModel.load()

        #expect(fixture.viewModel.hasActiveFilters == false)
        #expect(fixture.viewModel.selectedTimeRange == .all)
        guard case .loaded(let records) = fixture.viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        #expect(records.count == 3)
    }

    @Test("Loading without any history reports the empty state")
    func loadWithoutHistoryReportsEmpty() async throws {
        let fixture = try makeFixture(store: InMemoryCallDeskStore())

        await fixture.viewModel.load()

        #expect(fixture.viewModel.state == .empty)
        #expect(fixture.viewModel.hasActiveFilters == false)
    }

    @Test("A repository read failure reports the failed state")
    func repositoryFailureReportsFailedState() async throws {
        let fixture = try makeFixture()
        await fixture.store.setFailure(true, for: .fetchRecords)

        await fixture.viewModel.load()

        #expect(fixture.viewModel.state == .failed)
    }

    @Test("Deleting one record removes it from the list and the store")
    func deletingOneRecordRemovesIt() async throws {
        let fixture = try makeFixture()
        await fixture.viewModel.load()

        await fixture.viewModel.deleteRecords(ids: [fixedUUID(3)])

        guard case .loaded(let records) = fixture.viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        #expect(records.map(\.actionTitleSnapshot) == ["B002", "A001"])
        let persisted = try await fixture.repositories.history.fetch(.all)
        #expect(persisted.count == 2)
        #expect(fixture.viewModel.operationError == nil)
    }

    @Test("Deleting several records removes all of them at once")
    func deletingSeveralRecordsRemovesAllOfThem() async throws {
        let fixture = try makeFixture()
        await fixture.viewModel.load()

        await fixture.viewModel.deleteRecords(ids: [fixedUUID(1), fixedUUID(2)])

        guard case .loaded(let records) = fixture.viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        #expect(records.map(\.actionTitleSnapshot) == ["Pause"])
    }

    @Test("Deleting all records leaves the empty state")
    func deletingAllRecordsLeavesEmptyState() async throws {
        let fixture = try makeFixture()
        await fixture.viewModel.load()

        await fixture.viewModel.deleteAllRecords()

        #expect(fixture.viewModel.state == .empty)
        let persisted = try await fixture.repositories.history.fetch(.all)
        #expect(persisted.isEmpty)
    }

    @Test("A failing delete reports an operation error and keeps the list")
    func failingDeleteReportsOperationError() async throws {
        let fixture = try makeFixture()
        await fixture.viewModel.load()
        await fixture.store.setFailure(true, for: .deleteRecords)

        await fixture.viewModel.deleteRecords(ids: [fixedUUID(1)])

        #expect(fixture.viewModel.operationError == .deleteFailed)
        guard case .loaded(let records) = fixture.viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        #expect(records.count == 3)
    }

    @Test("A failing clear reports an operation error")
    func failingClearReportsOperationError() async throws {
        let fixture = try makeFixture()
        await fixture.viewModel.load()
        await fixture.store.setFailure(true, for: .deleteAllRecords)

        await fixture.viewModel.deleteAllRecords()

        #expect(fixture.viewModel.operationError == .clearFailed)
    }

    @Test("Recalling a record writes a fresh history entry from the snapshot")
    func recallWritesFreshHistoryEntry() async throws {
        let fixture = try makeFixture()
        await fixture.viewModel.load()

        await fixture.viewModel.recall(try #require(record(in: fixture, id: fixedUUID(3))))

        guard case .loaded(let records) = fixture.viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        #expect(records.count == 4)
        let newest = try #require(records.first)
        #expect(newest.actionTitleSnapshot == "Pause")
        #expect(newest.spokenTextSnapshot == "Service is paused")
        #expect(newest.result == .completed)
        #expect(fixture.viewModel.operationError == nil)
    }

    @Test("Recalling still works when the original action no longer exists")
    func recallWorksWithoutOriginalAction() async throws {
        // The snapshot carries identifiers of an action and a board that
        // were never created, mimicking business data deleted afterwards.
        let danglingRecord = try makeRecord(
            id: fixedUUID(9),
            actionID: fixedUUID(101),
            boardID: fixedUUID(102),
            title: "Ghost",
            speech: "Please call the ghost",
            startedAt: Date(timeIntervalSinceReferenceDate: 300),
            result: .completed
        )
        let fixture = try makeFixture(store: InMemoryCallDeskStore(records: [danglingRecord]))
        await fixture.viewModel.load()

        await fixture.viewModel.recall(danglingRecord)

        guard case .loaded(let records) = fixture.viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        #expect(records.count == 2)
        let newest = try #require(records.first)
        #expect(newest.result == .completed)
        // The repository rejects links to deleted objects, so the fresh
        // record is kept as a detached snapshot without identifiers.
        #expect(newest.actionID == nil)
        #expect(newest.boardID == nil)
        #expect(newest.spokenTextSnapshot == "Please call the ghost")
    }

    @Test("A failing recall reports an operation error and records the failure")
    func failingRecallReportsOperationError() async throws {
        let fixture = try makeFixture(speechDriver: FailingSpeechDriver())
        await fixture.viewModel.load()

        await fixture.viewModel.recall(try #require(record(in: fixture, id: fixedUUID(1))))

        #expect(fixture.viewModel.operationError == .recallFailed)
        guard case .loaded(let records) = fixture.viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        #expect(records.count == 4)
        #expect(records.first?.result == .failed)
    }

    // MARK: - Board scoping

    @Test("A board-scoped log only lists that board's records")
    @MainActor
    func boardScopedLoadFiltersOtherBoards() async throws {
        let boardA = fixedUUID(10)
        let boardB = fixedUUID(11)
        let store = try InMemoryCallDeskStore(
            records: [
                try makeRecord(
                    id: fixedUUID(1), boardID: boardA, title: "1",
                    speech: "1", startedAt: Date(), result: .completed
                ),
                try makeRecord(
                    id: fixedUUID(2), boardID: boardB, title: "2",
                    speech: "2", startedAt: Date(), result: .completed
                )
            ]
        )
        let fixture = try makeFixture(store: store)
        let viewModel = HistoryViewModel(
            history: fixture.repositories.history,
            callService: DefaultCallService(
                actions: fixture.repositories.actions,
                history: fixture.repositories.history,
                speechDriver: SilentCallSpeechDriver(utteranceDuration: 0)
            ),
            boardID: boardA
        )

        await viewModel.load()

        guard case .loaded(let records) = viewModel.state else {
            Issue.record("Expected loaded state")
            return
        }
        #expect(records.map(\.id) == [fixedUUID(1)])
    }

    @Test("Clearing a board-scoped log keeps other boards' records")
    @MainActor
    func boardScopedClearKeepsOtherBoards() async throws {
        let boardA = fixedUUID(10)
        let boardB = fixedUUID(11)
        let store = try InMemoryCallDeskStore(
            records: [
                try makeRecord(
                    id: fixedUUID(1), boardID: boardA, title: "1",
                    speech: "1", startedAt: Date(), result: .completed
                ),
                try makeRecord(
                    id: fixedUUID(2), boardID: boardB, title: "2",
                    speech: "2", startedAt: Date(), result: .completed
                )
            ]
        )
        let fixture = try makeFixture(store: store)
        let viewModel = HistoryViewModel(
            history: fixture.repositories.history,
            callService: DefaultCallService(
                actions: fixture.repositories.actions,
                history: fixture.repositories.history,
                speechDriver: SilentCallSpeechDriver(utteranceDuration: 0)
            ),
            boardID: boardA
        )
        await viewModel.load()

        await viewModel.deleteAllRecords()

        let remaining = try await fixture.repositories.history.fetch(.all)
        #expect(remaining.map(\.id) == [fixedUUID(2)])
    }

    // MARK: - Fixtures

    private struct Fixture {
        let store: InMemoryCallDeskStore
        let repositories: InMemoryRepositories
        let viewModel: HistoryViewModel
    }

    private func makeFixture(
        store: InMemoryCallDeskStore? = nil,
        speechDriver: any CallSpeechDriving = SilentCallSpeechDriver(utteranceDuration: 0),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) throws -> Fixture {
        let resolvedStore = try store ?? makeStore()
        let repositories = InMemoryRepositories(store: resolvedStore)
        // Retention is disabled so the fixed historic dates of the fixture
        // records survive the recall that a test triggers.
        let callService = DefaultCallService(
            actions: repositories.actions,
            history: repositories.history,
            settingsStore: InMemorySettingsStore(
                settings: CallDeskSettings(
                    history: try HistorySettings(retentionDays: 0, maximumRecordCount: 0)
                )
            ),
            speechDriver: speechDriver
        )
        let viewModel = HistoryViewModel(
            history: repositories.history,
            callService: callService,
            calendar: calendar,
            now: now
        )
        return Fixture(store: resolvedStore, repositories: repositories, viewModel: viewModel)
    }

    /// A fixture whose clock is frozen at noon GMT so day boundaries stay
    /// stable regardless of the machine's locale.
    private func makeTimeRangeFixture() throws -> Fixture {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = Date(timeIntervalSinceReferenceDate: 86_400 * 100 + 43_200)
        let store = try InMemoryCallDeskStore(
            records: [
                try makeRecord(
                    id: fixedUUID(1),
                    title: "Old",
                    speech: "Old call",
                    startedAt: now.addingTimeInterval(-20 * 86_400),
                    result: .completed
                ),
                try makeRecord(
                    id: fixedUUID(2),
                    title: "Recent",
                    speech: "Recent call",
                    startedAt: now.addingTimeInterval(-3 * 86_400),
                    result: .completed
                ),
                try makeRecord(
                    id: fixedUUID(3),
                    title: "Fresh",
                    speech: "Fresh call",
                    startedAt: now.addingTimeInterval(-3_600),
                    result: .completed
                )
            ]
        )
        return try makeFixture(store: store, calendar: calendar, now: { now })
    }

    private func record(in fixture: Fixture, id: UUID) -> CallRecord? {
        guard case .loaded(let records) = fixture.viewModel.state else {
            return nil
        }
        return records.first { $0.id == id }
    }

    private func makeStore() throws -> InMemoryCallDeskStore {
        let referenceDate = Date(timeIntervalSinceReferenceDate: 0)
        return try InMemoryCallDeskStore(
            records: [
                try makeRecord(
                    id: fixedUUID(1),
                    title: "A001",
                    speech: "Please call A001",
                    startedAt: referenceDate,
                    result: .completed
                ),
                try makeRecord(
                    id: fixedUUID(2),
                    title: "B002",
                    speech: "Please call B002",
                    startedAt: referenceDate.addingTimeInterval(60),
                    result: .failed,
                    errorDescription: "Output unavailable"
                ),
                try makeRecord(
                    id: fixedUUID(3),
                    title: "Pause",
                    speech: "Service is paused",
                    startedAt: referenceDate.addingTimeInterval(120),
                    result: .cancelled
                )
            ]
        )
    }

    private func makeRecord(
        id: UUID,
        actionID: UUID? = nil,
        boardID: UUID? = nil,
        title: String,
        speech: String,
        startedAt: Date,
        result: CallResult,
        errorDescription: String? = nil
    ) throws -> CallRecord {
        try CallRecord(
            id: id,
            actionID: actionID,
            boardID: boardID,
            actionTitleSnapshot: title,
            spokenTextSnapshot: speech,
            startedAt: startedAt,
            completedAt: startedAt.addingTimeInterval(1),
            result: result,
            errorDescription: errorDescription
        )
    }

    private func fixedUUID(_ value: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
    }
}

private nonisolated struct FailingSpeechDriver: CallSpeechDriving {
    struct DriverError: Error {}

    func announce(_ announcement: CallAnnouncement, voice: VoiceSettings, promptTone: PromptToneSettings) async throws {
        throw DriverError()
    }
}
