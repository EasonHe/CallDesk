import Combine
import Foundation

@MainActor
final class HistoryViewModel: ObservableObject {
    /// Preset lower bounds for the `startedAt` filter.
    enum TimeRange: CaseIterable, Equatable {
        case all
        case today
        case lastSevenDays
        case lastThirtyDays
    }

    /// A history operation that failed and needs user feedback.
    enum OperationError: Equatable {
        case deleteFailed
        case clearFailed
        case recallFailed
    }

    struct Query: Equatable {
        let searchText: String
        let selectedResult: CallResult?
        let selectedTimeRange: TimeRange
    }

    @Published private(set) var state: FeatureLoadState<[CallRecord]> = .loading
    @Published var searchText = ""
    @Published var selectedResult: CallResult?
    @Published var selectedTimeRange: TimeRange = .all
    @Published var operationError: OperationError?
    @Published private(set) var isRecalling = false

    private let history: any CallHistoryRepository
    private let callService: any CallService
    private let calendar: Calendar
    private let now: () -> Date
    /// Scopes the log to one board when set; nil shows everything.
    private let boardID: UUID?

    init(
        history: any CallHistoryRepository,
        callService: any CallService,
        boardID: UUID? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.history = history
        self.callService = callService
        self.boardID = boardID
        self.calendar = calendar
        self.now = now
    }

    convenience init(dependencies: AppDependencies, boardID: UUID? = nil) {
        self.init(history: dependencies.history, callService: dependencies.callService, boardID: boardID)
    }

    var query: Query {
        Query(
            searchText: searchText,
            selectedResult: selectedResult,
            selectedTimeRange: selectedTimeRange
        )
    }

    var hasActiveFilters: Bool {
        selectedResult != nil
            || selectedTimeRange != .all
            || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func load() async {
        state = .loading
        do {
            let filter = try CallHistoryFilter(
                startedFrom: startDate(for: selectedTimeRange),
                boardID: boardID,
                results: selectedResult.map { [$0] } ?? [],
                searchText: searchText
            )
            let records = try await history.fetch(filter)
            state = records.isEmpty ? .empty : .loaded(records)
        } catch {
            state = .failed
        }
    }

    func clearFilters() {
        searchText = ""
        selectedResult = nil
        selectedTimeRange = .all
    }

    func deleteRecords(ids: Set<UUID>) async {
        guard !ids.isEmpty else {
            return
        }
        do {
            try await history.delete(ids: ids)
            await load()
        } catch {
            operationError = .deleteFailed
        }
    }

    /// Clears history; when scoped to a board only that board's records
    /// are removed, so other boards keep their logs intact.
    func deleteAllRecords() async {
        do {
            if let boardID {
                guard let filter = try? CallHistoryFilter(boardID: boardID) else {
                    operationError = .clearFailed
                    return
                }
                let records = try await history.fetch(filter)
                if !records.isEmpty {
                    try await history.delete(ids: Set(records.map(\.id)))
                }
            } else {
                try await history.deleteAll()
            }
            await load()
        } catch {
            operationError = .clearFailed
        }
    }

    /// Replays the record's snapshot through the call service and reloads
    /// the list so the freshly written history entry appears right away.
    func recall(_ record: CallRecord) async {
        guard !isRecalling else {
            return
        }
        isRecalling = true
        defer {
            isRecalling = false
        }

        let result = await callService.requestRecall(from: record)
        if case .failed = result {
            operationError = .recallFailed
        }
        await load()
    }

    private func startDate(for timeRange: TimeRange) -> Date? {
        switch timeRange {
        case .all:
            return nil
        case .today:
            return calendar.startOfDay(for: now())
        case .lastSevenDays:
            return calendar.date(byAdding: .day, value: -7, to: now())
        case .lastThirtyDays:
            return calendar.date(byAdding: .day, value: -30, to: now())
        }
    }
}
