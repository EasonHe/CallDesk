import Combine
import Foundation
import Testing
@testable import CallDesk

@MainActor
@Suite("External display presenter")
struct ExternalDisplayPresenterTests {
    @Test("The presentation mirrors the live call from the service")
    func presentationMirrorsLiveCall() async throws {
        let fixture = try Fixture()

        let speaking = try LiveCallState(
            title: "A001",
            spokenText: "Please call A001",
            phase: .speaking,
            startedAt: Fixture.referenceDate
        )
        fixture.service.send(speaking)

        #expect(fixture.presenter.presentation.liveCall == speaking)
    }

    @Test("A completed call refreshes the recent call rows")
    func completedCallRefreshesRecentCalls() async throws {
        let fixture = try Fixture()
        try await fixture.saveCompletedRecord(title: "A007")
        fixture.presenter.displayDidConnect()

        let completed = try LiveCallState(
            title: "A007",
            spokenText: "Please call A007",
            phase: .completed,
            startedAt: Fixture.referenceDate
        )
        fixture.service.send(completed)
        await waitUntil("the recent call rows are loaded") {
            !fixture.presenter.presentation.recentCalls.isEmpty
        }

        #expect(fixture.presenter.presentation.recentCalls.map(\.title) == ["A007"])
    }

    @Test("A speaking update keeps the previous recent call rows")
    func speakingUpdateKeepsRecentCalls() async throws {
        let fixture = try Fixture()
        try await fixture.saveCompletedRecord(title: "A001")
        fixture.presenter.displayDidConnect()
        fixture.service.send(
            try LiveCallState(title: "A001", spokenText: "Text", phase: .completed)
        )
        await waitUntil("the recent call rows are loaded") {
            !fixture.presenter.presentation.recentCalls.isEmpty
        }

        fixture.service.send(
            try LiveCallState(title: "A002", spokenText: "Text", phase: .speaking)
        )

        #expect(fixture.presenter.presentation.recentCalls.map(\.title) == ["A001"])
        #expect(fixture.presenter.presentation.liveCall.phase == .speaking)
    }

    @Test("A recent call count of zero clears the rows")
    func zeroRecentCallCountClearsRows() async throws {
        let fixture = try Fixture(recentCallCount: 0)
        try await fixture.saveCompletedRecord(title: "A001")

        fixture.service.send(
            try LiveCallState(title: "A001", spokenText: "Text", phase: .completed)
        )
        await waitUntil("the refresh has settled") {
            fixture.presenter.presentation.liveCall.phase == .completed
        }

        #expect(fixture.presenter.presentation.recentCalls.isEmpty)
    }

    @Test("Saving display settings immediately updates the restaurant title")
    func savingDisplaySettingsImmediatelyUpdatesRestaurantTitle() throws {
        let fixture = try Fixture()

        fixture.settingsStore.save(
            CallDeskSettings(
                display: try DisplaySettings(
                    recentCallCount: 6,
                    restaurantTitle: "幸福餐厅"
                )
            )
        )

        #expect(fixture.presenter.displaySettings.restaurantTitle == "幸福餐厅")
    }

    @Test("The presenter exposes the display settings loaded at initialization")
    func presenterExposesLoadedDisplaySettings() throws {
        let expectedSettings = try DisplaySettings(
            recentCallCount: 3,
            restaurantTitle: "幸福餐厅"
        )
        let fixture = try Fixture(
            recentCallCount: expectedSettings.recentCallCount,
            restaurantTitle: expectedSettings.restaurantTitle
        )

        #expect(fixture.presenter.displaySettings == expectedSettings)
    }

    @Test("A title-only display settings change preserves loaded recent call order")
    func titleOnlyDisplaySettingsChangePreservesLoadedRecentCallOrder() async throws {
        let fixture = try Fixture(recentCallCount: 6)
        try await fixture.saveCompletedRecord(
            title: "A001",
            startedAt: Fixture.referenceDate.addingTimeInterval(-60)
        )
        try await fixture.saveCompletedRecord(
            title: "A002",
            startedAt: Fixture.referenceDate.addingTimeInterval(-30)
        )

        fixture.presenter.displayDidConnect()
        await waitUntil("the recent call rows are loaded") {
            fixture.presenter.presentation.recentCalls.count == 2
        }
        let recentCallsBeforeTitleChange = fixture.presenter.presentation.recentCalls

        fixture.settingsStore.save(
            CallDeskSettings(
                display: try DisplaySettings(
                    recentCallCount: 6,
                    restaurantTitle: "幸福餐厅"
                )
            )
        )

        #expect(fixture.presenter.presentation.recentCalls == recentCallsBeforeTitleChange)
        #expect(fixture.presenter.presentation.recentCalls.map(\.title) == ["A002", "A001"])
    }

    @Test("A title-only display settings change does not fetch recent calls again")
    func titleOnlyDisplaySettingsChangeDoesNotFetchRecentCallsAgain() async throws {
        let fixture = try Fixture(recentCallCount: 6)
        try await fixture.saveCompletedRecord(
            title: "A001",
            startedAt: Fixture.referenceDate.addingTimeInterval(-60)
        )
        try await fixture.saveCompletedRecord(
            title: "A002",
            startedAt: Fixture.referenceDate.addingTimeInterval(-30)
        )
        fixture.presenter.displayDidConnect()

        fixture.service.send(
            try LiveCallState(title: "A002", spokenText: "Text", phase: .completed)
        )
        await waitUntil("the recent call rows are loaded") {
            fixture.presenter.presentation.recentCalls.count == 2
        }
        let fetchCountAfterInitialLoad = fixture.history.fetchCount

        fixture.settingsStore.save(
            CallDeskSettings(
                display: try DisplaySettings(
                    recentCallCount: 6,
                    restaurantTitle: "幸福餐厅"
                )
            )
        )
        for _ in 0..<10 {
            await Task.yield()
        }

        #expect(fixture.history.fetchCount == fetchCountAfterInitialLoad)
    }

    @Test("Changing recent call count refreshes the loaded recent call rows")
    func changingRecentCallCountRefreshesLoadedRecentCallRows() async throws {
        let fixture = try Fixture(recentCallCount: 6)
        try await fixture.saveCompletedRecord(
            title: "A001",
            startedAt: Fixture.referenceDate.addingTimeInterval(-60)
        )
        try await fixture.saveCompletedRecord(
            title: "A002",
            startedAt: Fixture.referenceDate.addingTimeInterval(-30)
        )

        fixture.presenter.displayDidConnect()
        await waitUntil("the recent call rows are loaded") {
            fixture.presenter.presentation.recentCalls.count == 2
        }

        fixture.settingsStore.save(
            CallDeskSettings(display: try DisplaySettings(recentCallCount: 1))
        )
        await waitUntil("the recent call rows reflect the new count") {
            fixture.presenter.presentation.recentCalls.count == 1
        }

        #expect(fixture.presenter.displaySettings.recentCallCount == 1)
        #expect(fixture.presenter.presentation.recentCalls.map(\.title) == ["A002"])
    }

    @Test("A configured count above six remains available to the display")
    func configuredCountAboveSixRemainsAvailable() async throws {
        let fixture = try Fixture(recentCallCount: 8)
        for index in 1...8 {
            try await fixture.saveCompletedRecord(
                title: "A00\(index)",
                startedAt: Fixture.referenceDate.addingTimeInterval(Double(index))
            )
        }

        fixture.presenter.displayDidConnect()
        await waitUntil("eight recent calls are loaded") {
            fixture.presenter.presentation.recentCalls.count == 8
        }

        #expect(fixture.presenter.presentation.recentCalls.map(\.title) == [
            "A008", "A007", "A006", "A005", "A004", "A003", "A002", "A001"
        ])
    }

    @Test("Connect and disconnect update the published connection state")
    func connectAndDisconnectUpdateConnectionState() throws {
        let fixture = try Fixture()
        #expect(!fixture.presenter.isConnected)

        fixture.presenter.displayDidConnect()
        #expect(fixture.presenter.isConnected)

        fixture.presenter.displayDidDisconnect()
        #expect(!fixture.presenter.isConnected)
    }

    @Test("Only completed records appear in the recent call rows")
    func onlyCompletedRecordsAppear() async throws {
        let fixture = try Fixture()
        try await fixture.saveCompletedRecord(title: "A001")
        try await fixture.repositories.history.save(
            try CallRecord(
                actionTitleSnapshot: "A002",
                spokenTextSnapshot: "Please call A002",
                startedAt: Fixture.referenceDate,
                completedAt: Fixture.referenceDate,
                result: .cancelled
            )
        )

        fixture.presenter.displayDidConnect()
        await waitUntil("the recent call rows are loaded") {
            !fixture.presenter.presentation.recentCalls.isEmpty
        }

        #expect(fixture.presenter.presentation.recentCalls.map(\.title) == ["A001"])
    }

    @Test("Re-calling the same number does not duplicate the recent call rows")
    func recallingSameNumberDoesNotDuplicateRows() async throws {
        let fixture = try Fixture()
        let workspaceID = UUID()
        let boardID = UUID()
        let actionID = UUID()
        try await fixture.repositories.workspaces.save(
            try Workspace(id: workspaceID, name: "Operations")
        )
        try await fixture.repositories.boards.save(
            try CallBoard(id: boardID, workspaceID: workspaceID, name: "Queue", sortOrder: 0)
        )
        try await fixture.repositories.actions.save(
            try CallAction(id: actionID, boardID: boardID, title: "A021", speechText: "Please call A021")
        )
        try await fixture.saveCompletedRecord(
            title: "A021",
            actionID: actionID,
            startedAt: Fixture.referenceDate.addingTimeInterval(-60)
        )
        try await fixture.saveCompletedRecord(
            title: "A020",
            startedAt: Fixture.referenceDate.addingTimeInterval(-45)
        )
        try await fixture.saveCompletedRecord(
            title: "A021",
            actionID: actionID,
            startedAt: Fixture.referenceDate.addingTimeInterval(-30)
        )

        fixture.presenter.displayDidConnect()
        await waitUntil("the recent call rows are loaded") {
            fixture.presenter.presentation.recentCalls.count == 2
        }

        #expect(fixture.presenter.presentation.recentCalls.map(\.title) == ["A021", "A020"])
    }

    @Test("Re-calling a non-first recent number preserves its card position")
    func recallingNonFirstNumberPreservesRecentCardPosition() async throws {
        let fixture = try Fixture()
        let recalledActionID = try await fixture.makeAction(title: "A021")
        let newerActionID = try await fixture.makeAction(title: "A022")
        try await fixture.saveCompletedRecord(
            title: "A021",
            actionID: recalledActionID,
            startedAt: Fixture.referenceDate.addingTimeInterval(-60)
        )
        try await fixture.saveCompletedRecord(
            title: "A022",
            actionID: newerActionID,
            startedAt: Fixture.referenceDate.addingTimeInterval(-30)
        )

        fixture.presenter.displayDidConnect()
        await waitUntil("the initial recent rows are loaded") {
            fixture.presenter.presentation.recentCalls.map(\.title) == ["A022", "A021"]
        }

        try await fixture.saveCompletedRecord(
            title: "A021",
            actionID: recalledActionID,
            startedAt: Fixture.referenceDate
        )
        fixture.service.send(
            try LiveCallState(
                actionID: recalledActionID,
                title: "A021",
                spokenText: "Please call A021",
                phase: .completed,
                startedAt: Fixture.referenceDate
            )
        )
        await waitUntil("the recalled row refresh is applied") {
            fixture.presenter.presentation.recentCalls.count == 2
                && fixture.presenter.presentation.recentCalls[1].title == "A021"
                && fixture.presenter.presentation.recentCalls[1].calledAt
                    == Fixture.referenceDate.addingTimeInterval(1)
        }

        #expect(fixture.presenter.presentation.recentCalls.map(\.title) == ["A022", "A021"])
    }

    @Test("A newly completed number still enters the recent cards first")
    func newlyCompletedNumberEntersRecentCardsFirst() async throws {
        let fixture = try Fixture()
        try await fixture.saveCompletedRecord(
            title: "A021",
            actionID: try await fixture.makeAction(title: "A021"),
            startedAt: Fixture.referenceDate.addingTimeInterval(-60)
        )
        try await fixture.saveCompletedRecord(
            title: "A022",
            actionID: try await fixture.makeAction(title: "A022"),
            startedAt: Fixture.referenceDate.addingTimeInterval(-30)
        )
        fixture.presenter.displayDidConnect()
        await waitUntil("the initial recent rows are loaded") {
            fixture.presenter.presentation.recentCalls.map(\.title) == ["A022", "A021"]
        }

        let newActionID = try await fixture.makeAction(title: "A023")
        try await fixture.saveCompletedRecord(
            title: "A023",
            actionID: newActionID,
            startedAt: Fixture.referenceDate
        )
        fixture.service.send(
            try LiveCallState(
                actionID: newActionID,
                title: "A023",
                spokenText: "Please call A023",
                phase: .completed,
                startedAt: Fixture.referenceDate
            )
        )
        await waitUntil("the newly completed row refresh is applied") {
            fixture.presenter.presentation.recentCalls.first?.title == "A023"
                && fixture.presenter.presentation.recentCalls.first?.calledAt
                    == Fixture.referenceDate.addingTimeInterval(1)
        }

        #expect(fixture.presenter.presentation.recentCalls.map(\.title) == ["A023", "A022", "A021"])
    }

    // MARK: - Helpers

    private func waitUntil(
        _ description: String,
        condition: () async -> Bool
    ) async {
        for _ in 0..<500 {
            if await condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        Issue.record("Timed out waiting until \(description)")
    }

    @MainActor
    private struct Fixture {
        static let referenceDate = Date(timeIntervalSinceReferenceDate: 100)

        let service = StubCallService()
        let repositories: InMemoryRepositories
        let settingsStore: InMemorySettingsStore
        let history: FetchCountingHistoryRepository
        let presenter: ExternalDisplayPresenter

        init(
            recentCallCount: Int = 5,
            restaurantTitle: String = DisplaySettings.defaultRestaurantTitle
        ) throws {
            repositories = try InMemoryRepositories.empty()
            let settings = CallDeskSettings(
                display: try DisplaySettings(
                    recentCallCount: recentCallCount,
                    restaurantTitle: restaurantTitle
                )
            )
            settingsStore = InMemorySettingsStore(settings: settings)
            history = FetchCountingHistoryRepository(repository: repositories.history)
            let referenceDate = Self.referenceDate
            presenter = ExternalDisplayPresenter(
                callService: service,
                history: history,
                settingsStore: settingsStore,
                now: { referenceDate }
            )
        }

        func saveCompletedRecord(
            title: String,
            actionID: UUID? = nil,
            startedAt: Date = referenceDate.addingTimeInterval(-60)
        ) async throws {
            try await repositories.history.save(
                try CallRecord(
                    actionID: actionID,
                    actionTitleSnapshot: title,
                    spokenTextSnapshot: "Please call \(title)",
                    startedAt: startedAt,
                    completedAt: startedAt.addingTimeInterval(1),
                    result: .completed
                )
            )
        }

        /// Saves an action inside its own workspace and board, so history
        /// records can reference a real action the way production does.
        @discardableResult
        func makeAction(id: UUID = UUID(), title: String) async throws -> UUID {
            let workspaceID = UUID()
            let boardID = UUID()
            try await repositories.workspaces.save(
                try Workspace(id: workspaceID, name: "Operations")
            )
            try await repositories.boards.save(
                try CallBoard(id: boardID, workspaceID: workspaceID, name: "Queue", sortOrder: 0)
            )
            try await repositories.actions.save(
                try CallAction(id: id, boardID: boardID, title: title, speechText: "Please call \(title)")
            )
            return id
        }
    }
}

/// A call service stub whose live call state is driven by the test.
@MainActor
private final class StubCallService: CallService {
    private let subject = CurrentValueSubject<LiveCallState, Never>(.idle)

    var liveCallState: LiveCallState { subject.value }

    var liveCallStatePublisher: AnyPublisher<LiveCallState, Never> {
        subject.eraseToAnyPublisher()
    }

    var activeSession: CallingSession? { nil }

    var pendingActionIDs: Set<UUID> { [] }

    var lastCompletedCallRecordID: UUID? { nil }

    func send(_ state: LiveCallState) {
        subject.send(state)
    }

    @discardableResult
    func requestCall(_ request: CallingRequest) async -> CallingResult {
        .cancelled
    }

    @discardableResult
    func requestRecall(from record: CallRecord) async -> CallingResult {
        .cancelled
    }

    func cancelActiveCall() async {}

    func cancelPendingAction(actionID: UUID) async {}
}

/// Forwards history operations while recording presenter fetches.
private final class FetchCountingHistoryRepository: CallHistoryRepository, @unchecked Sendable {
    private let repository: any CallHistoryRepository
    private let lock = NSLock()
    private var storedFetchCount = 0

    var fetchCount: Int {
        lock.withLock { storedFetchCount }
    }

    init(repository: any CallHistoryRepository) {
        self.repository = repository
    }

    func save(_ record: CallRecord) async throws {
        try await repository.save(record)
    }

    func record(id: UUID) async throws -> CallRecord? {
        try await repository.record(id: id)
    }

    func fetch(_ filter: CallHistoryFilter) async throws -> [CallRecord] {
        lock.withLock { storedFetchCount += 1 }
        return try await repository.fetch(filter)
    }

    func delete(ids: Set<UUID>) async throws {
        try await repository.delete(ids: ids)
    }

    func deleteAll() async throws {
        try await repository.deleteAll()
    }

    func enforceRetention(
        _ policy: HistoryRetentionPolicy,
        now: Date
    ) async throws -> Int {
        try await repository.enforceRetention(policy, now: now)
    }
}
