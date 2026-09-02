import Foundation
import Testing
@testable import CallDesk

@MainActor
@Suite("Board statistics view model")
struct BoardStatisticsViewModelTests {
    private static let boardID = fixedUUID(2)

    @Test("Loading aggregates records for the board")
    func loadAggregatesForBoard() async throws {
        let store = try Self.makeStore()
        let viewModel = BoardStatisticsViewModel(
            boardID: Self.boardID,
            history: InMemoryRepositories(store: store).history,
            calendar: Self.calendar,
            now: { Self.referenceDay }
        )

        await viewModel.load()

        guard case .loaded(let stats) = viewModel.state else {
            Issue.record("expected loaded state")
            return
        }
        #expect(stats.todayCount == 4)
    }

    @Test("Default period is week")
    func defaultPeriodIsWeek() throws {
        let store = try InMemoryCallDeskStore()
        let viewModel = BoardStatisticsViewModel(
            boardID: Self.boardID,
            history: InMemoryRepositories(store: store).history
        )
        #expect(viewModel.selectedPeriod == .week)
    }

    @Test("Empty board reports the empty state")
    func emptyBoardReportsEmpty() async throws {
        let store = try InMemoryCallDeskStore(
            workspaces: [try Workspace(id: Self.workspaceID, name: "Ops")]
        )
        let viewModel = BoardStatisticsViewModel(
            boardID: Self.boardID,
            history: InMemoryRepositories(store: store).history,
            now: { Self.referenceDay }
        )
        await viewModel.load()
        #expect(viewModel.state == .empty)
    }

    @Test("Records for other boards are excluded from statistics")
    func otherBoardRecordsExcluded() async throws {
        let otherBoardID = Self.fixedUUID(3)
        let store = try InMemoryCallDeskStore(
            workspaces: [try Workspace(id: Self.workspaceID, name: "Ops")],
            boards: [
                CallBoard(id: Self.boardID, workspaceID: Self.workspaceID, name: "Queue", sortOrder: 0),
                CallBoard(id: otherBoardID, workspaceID: Self.workspaceID, name: "Other", sortOrder: 1)
            ],
            actions: [
                CallAction(id: Self.fixedUUID(10), boardID: Self.boardID, title: "6", speechText: "6", sortOrder: 0),
                CallAction(id: Self.fixedUUID(11), boardID: otherBoardID, title: "9", speechText: "9", sortOrder: 0)
            ],
            records: [
                CallRecord(
                    actionID: Self.fixedUUID(10),
                    boardID: Self.boardID,
                    actionTitleSnapshot: "4",
                    spokenTextSnapshot: "4",
                    startedAt: Self.referenceDay,
                    completedAt: Self.referenceDay.addingTimeInterval(5),
                    result: .completed
                ),
                CallRecord(
                    actionID: Self.fixedUUID(11),
                    boardID: otherBoardID,
                    actionTitleSnapshot: "9",
                    spokenTextSnapshot: "9",
                    startedAt: Self.referenceDay,
                    completedAt: Self.referenceDay.addingTimeInterval(5),
                    result: .completed
                )
            ]
        )
        let viewModel = BoardStatisticsViewModel(
            boardID: Self.boardID,
            history: InMemoryRepositories(store: store).history,
            calendar: Self.calendar,
            now: { Self.referenceDay }
        )

        await viewModel.load()

        guard case .loaded(let stats) = viewModel.state else {
            Issue.record("expected loaded state")
            return
        }
        #expect(stats.todayCount == 4)
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    private static var referenceDay: Date {
        Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14
    }

    private static let workspaceID = fixedUUID(1)

    private static func makeStore() throws -> InMemoryCallDeskStore {
        try InMemoryCallDeskStore(
            workspaces: [try Workspace(id: workspaceID, name: "Ops")],
            boards: [
                CallBoard(id: boardID, workspaceID: workspaceID, name: "Queue", sortOrder: 0)
            ],
            actions: [
                CallAction(id: Self.fixedUUID(10), boardID: boardID, title: "6", speechText: "6", sortOrder: 0)
            ],
            records: [
                CallRecord(
                    actionID: Self.fixedUUID(10),
                    boardID: boardID,
                    actionTitleSnapshot: "4",
                    spokenTextSnapshot: "4",
                    startedAt: referenceDay,
                    completedAt: referenceDay.addingTimeInterval(5),
                    result: .completed
                )
            ]
        )
    }

    private static func fixedUUID(_ value: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
    }
}