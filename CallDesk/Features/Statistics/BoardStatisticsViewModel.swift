import Combine
import Foundation

@MainActor
final class BoardStatisticsViewModel: ObservableObject {
    enum Period: String, CaseIterable, Identifiable {
        case day
        case week
        case month
        case year

        var id: String { rawValue }
        var title: String {
            switch self {
            case .day: "日"
            case .week: "周"
            case .month: "月"
            case .year: "年"
            }
        }
    }

    @Published private(set) var state: FeatureLoadState<BoardStatisticsService.Statistics> = .loading
    @Published var selectedPeriod: Period = .week

    private let boardID: UUID
    private let history: any CallHistoryRepository
    private let calendar: Calendar
    private let now: () -> Date

    init(
        boardID: UUID,
        history: any CallHistoryRepository,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.boardID = boardID
        self.history = history
        self.calendar = calendar
        self.now = now
    }

    convenience init(boardID: UUID, dependencies: AppDependencies) {
        self.init(boardID: boardID, history: dependencies.history)
    }

    func load() async {
        state = .loading
        await fetch()
    }

    /// Silent refresh used by pull-to-refresh and the tab-switch token: the
    /// visible numbers stay on screen until the new ones arrive, so the
    /// page never flickers back to a spinner.
    func reload() async {
        await fetch()
    }

    private func fetch() async {
        do {
            let filter = try CallHistoryFilter(boardID: boardID)
            let records = try await history.fetch(filter)
            guard !records.isEmpty else {
                state = .empty
                return
            }
            // Keep the heavy aggregation off the main actor; the service is
            // pure and Sendable so it can run on a background task.
            let boardID = boardID
            let calendar = calendar
            let now = now()
            let statistics = await computeStatistics(boardID: boardID, records: records, calendar: calendar, now: now)
            state = .loaded(statistics)
        } catch {
            state = .failed
        }
    }

    private func computeStatistics(
        boardID: UUID,
        records: [CallRecord],
        calendar: Calendar,
        now: Date
    ) async -> BoardStatisticsService.Statistics {
        let computation = Task.detached(priority: .userInitiated) {
            BoardStatisticsService.statistics(boardID: boardID, records: records, calendar: calendar, now: now)
        }
        return await computation.value
    }
}