import Combine
import Foundation

/// Builds the read-only presentation for an external (second) display.
///
/// The presenter mirrors the live call from `CallService` and keeps a
/// short list of recently completed calls from the history repository.
/// It never starts or changes calls, so the external screen stays a
/// pure output surface and the calling flow is untouched.
@MainActor
final class ExternalDisplayPresenter: ObservableObject, ExternalDisplayMonitoring {
    @Published private(set) var presentation: DisplayPresentationState
    @Published private(set) var displaySettings: DisplaySettings
    @Published private(set) var isConnected = false

    private let callService: any CallService
    private let history: any CallHistoryRepository
    private let settingsStore: any SettingsStore
    private let now: @Sendable () -> Date
    private var liveCallSubscription: AnyCancellable?
    private var settingsSubscription: AnyCancellable?
    private var refreshTask: Task<Void, Never>?

    init(
        callService: any CallService,
        history: any CallHistoryRepository,
        settingsStore: any SettingsStore,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.callService = callService
        self.history = history
        self.settingsStore = settingsStore
        self.now = now
        displaySettings = settingsStore.load().display
        presentation = DisplayPresentationState(
            liveCall: callService.liveCallState,
            updatedAt: now()
        )
        liveCallSubscription = callService.liveCallStatePublisher
            .sink { [weak self] liveCall in
                self?.apply(liveCall)
            }
        settingsSubscription = settingsStore.settingsPublisher
            .sink { [weak self] settings in
                self?.apply(settings.display)
            }
    }

    var isConnectedPublisher: AnyPublisher<Bool, Never> {
        $isConnected.eraseToAnyPublisher()
    }

    /// Called by the external scene delegate when the display connects.
    func displayDidConnect() {
        isConnected = true
        refreshRecentCalls()
    }

    /// Called by the external scene delegate when the display goes away.
    func displayDidDisconnect() {
        isConnected = false
        refreshTask?.cancel()
        refreshTask = nil
        presentation = presentation.withRecentCalls([])
    }

    // MARK: - Private

    private func apply(_ liveCall: LiveCallState) {
        presentation = DisplayPresentationState(
            liveCall: liveCall,
            recentCalls: presentation.recentCalls,
            updatedAt: now()
        )
        // Only a completed call adds a history row worth showing.
        if isConnected, liveCall.phase == .completed {
            refreshRecentCalls(preservingPositionFor: liveCall)
        }
    }

    private func apply(_ settings: DisplaySettings) {
        let recentCallCountDidChange = displaySettings.recentCallCount != settings.recentCallCount
        displaySettings = settings
        if isConnected, recentCallCountDidChange {
            refreshRecentCalls()
        }
    }

    private func refreshRecentCalls(
        preservingPositionFor completedCall: LiveCallState? = nil
    ) {
        guard isConnected else {
            return
        }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.loadRecentCalls(preservingPositionFor: completedCall)
        }
    }

    /// Best effort, like every other read for a passive surface: a failed
    /// fetch keeps the previous rows instead of surfacing an error.
    private func loadRecentCalls(
        preservingPositionFor completedCall: LiveCallState? = nil
    ) async {
        let recentCallCount = displaySettings.recentCallCount
        guard recentCallCount > 0 else {
            presentation = presentation.withRecentCalls([])
            return
        }

        // Fetch a wider window than the visible count so the board can still
        // be filled with distinct numbers after duplicates are removed.
        let batchLimit = max(recentCallCount * 4, 20)
        guard
            let filter = try? CallHistoryFilter(results: [.completed], limit: batchLimit),
            let records = try? await history.fetch(filter),
            !Task.isCancelled
        else {
            return
        }

        let recentCalls = Self.distinctMostRecent(records)
            .prefix(recentCallCount)
            .compactMap { record in
                try? RecentCallPresentation(
                    id: record.id,
                    actionID: record.actionID,
                    title: record.actionTitleSnapshot,
                    spokenText: record.spokenTextSnapshot,
                    calledAt: record.completedAt ?? record.startedAt
                )
            }
        presentation = presentation.withRecentCalls(
            recentCallsPreservingPositionIfNeeded(
                recentCalls,
                for: completedCall
            )
        )
    }

    /// A recall refreshes the data for an existing card without moving that
    /// card. This keeps the external display stable while a staff member
    /// replays an earlier call. Calls that are not already visible retain the
    /// repository's newest-first ordering.
    private func recentCallsPreservingPositionIfNeeded(
        _ recentCalls: [RecentCallPresentation],
        for completedCall: LiveCallState?
    ) -> [RecentCallPresentation] {
        guard let completedCall,
              let existingIndex = presentation.recentCalls.firstIndex(
                where: { Self.matches($0, completedCall: completedCall) }
              ),
              let refreshedIndex = recentCalls.firstIndex(
                where: { Self.matches($0, completedCall: completedCall) }
              )
        else {
            return recentCalls
        }

        var calls = recentCalls
        let refreshedCall = calls.remove(at: refreshedIndex)
        calls.insert(refreshedCall, at: min(existingIndex, calls.count))
        return calls
    }

    /// Prefer a persistent action identifier. Detached calls have no action
    /// identifier, so their trimmed title is used as a stable fallback.
    private static func matches(
        _ recentCall: RecentCallPresentation,
        completedCall: LiveCallState
    ) -> Bool {
        if let actionID = completedCall.actionID {
            return recentCall.actionID == actionID
        }

        guard let title = completedCall.title?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return recentCall.actionID == nil && recentCall.title == title
    }

    /// Keeps the most recent completed record per call action so the board
    /// never shows the same number twice. Records arrive newest-first.
    private static func distinctMostRecent(_ records: [CallRecord]) -> [CallRecord] {
        var seenKeys = Set<String>()
        var distinctRecords: [CallRecord] = []
        for record in records {
            let key = record.actionID?.uuidString ?? record.actionTitleSnapshot
            guard seenKeys.insert(key).inserted else {
                continue
            }
            distinctRecords.append(record)
        }
        return distinctRecords
    }
}
