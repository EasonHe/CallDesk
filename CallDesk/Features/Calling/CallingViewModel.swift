import Combine
import Foundation
import os.log

@MainActor
final class CallingViewModel: ObservableObject {
    struct Content: Equatable {
        let workspaceName: String
        let boards: [CallBoard]
        let selectedBoardID: UUID
        let actions: [CallAction]

        var selectedBoard: CallBoard? {
            boards.first { $0.id == selectedBoardID }
        }
    }

    /// Why the last call did not announce anything.
    enum CallOutcomeFailure: Equatable {
        /// The audio session was taken over mid-announcement (a phone call,
        /// another app claiming the output).
        case interrupted
        /// Speech playback itself failed, carrying the underlying message.
        case failed(String)
    }

    @Published private(set) var state: FeatureLoadState<Content> = .loading
    @Published private(set) var liveCall: LiveCallState = .idle

    /// Action IDs that have completed a call. The calling view uses this to
    /// tint called tiles so the operator can see at a glance which numbers
    /// still need to be called. The set is persisted through
    /// `calledMarkers` and restored on launch, so progress survives app
    /// restarts and board switches.
    @Published private(set) var calledActionIDs: Set<UUID> = []

    /// Action IDs that are running or waiting in the queue, mirrored from
    /// the call service so tiles can show a requested-but-not-finished
    /// tint.
    @Published private(set) var pendingActionIDs: Set<UUID> = []

    /// A call that ended without announcing anything, so the operator knows
    /// the number did not actually go out. Cleared when a new call starts
    /// or when the operator dismisses the message.
    @Published private(set) var callOutcomeFailure: CallOutcomeFailure?

    /// The action selected with the hardware keyboard or remote. Drives a
    /// highlight on the grid and lets the operator trigger a call with a
    /// single confirm key instead of a tap.
    @Published private(set) var selectedActionID: UUID?

    /// Whether tile taps should fire a haptic. Follows Settings in real time.
    @Published private(set) var hapticFeedbackEnabled: Bool = true

    /// Whether tiles show their detail text under the number. Follows
    /// Settings in real time so toggling "Show Action Detail" restyles the
    /// grid immediately.
    @Published private(set) var showsActionDetail: Bool = true

    /// The action ID of the most recent completed call, restored from
    /// history on launch so the long-press undo gesture works again after
    /// the app is reopened. Only set for records that still have an action
    /// link; detached records (action deleted) have no tile to undo.
    @Published private(set) var lastCalledActionID: UUID?

    /// The history record of the most recent completed call, so undo does
    /// not depend on the service's memory-only bookkeeping after a relaunch.
    private var lastCompletedRecordID: UUID?

    /// Why the last undo attempt could not remove the history record.
    @Published private(set) var undoFailed = false

    private let workspaces: any WorkspaceRepository
    private let boards: any CallBoardRepository
    private let actions: any CallActionRepository
    private let callService: any CallService
    private let history: any CallHistoryRepository
    private let calledMarkers: any CalledMarkersStoring
    private let calendar: Calendar
    private let now: () -> Date
    private var liveCallSubscription: AnyCancellable?
    private var settingsSubscription: AnyCancellable?
    /// Keeps the nightly reset loop alive; cancelled together with the
    /// view model so previews and tests never leave stray tasks behind.
    private var midnightResetTask: Task<Void, Never>?
    private var hasLoaded = false
    /// The action ID that was active most recently; used to detect the
    /// moment a call transitions from "in-flight" to "completed" so the
    /// tile can flip to the called tint.
    private var lastActiveActionID: UUID?
    /// While a cancellation is in flight the tile already reverted locally,
    /// so intermediate live-call updates and finishing request tasks must
    /// not re-apply the not-yet cleaned-up service state and flash the
    /// pending tint again.
    private var isCancellingPendingAction = false

    init(
        workspaces: any WorkspaceRepository,
        boards: any CallBoardRepository,
        actions: any CallActionRepository,
        callService: any CallService,
        history: any CallHistoryRepository,
        calledMarkers: any CalledMarkersStoring = InMemoryCalledMarkersStore(),
        settingsStore: any SettingsStore = UserDefaultsSettingsStore(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.workspaces = workspaces
        self.boards = boards
        self.actions = actions
        self.callService = callService
        self.history = history
        self.calledMarkers = calledMarkers
        self.calendar = calendar
        self.now = now
        liveCall = callService.liveCallState
        lastActiveActionID = liveCall.actionID
        liveCallSubscription = callService.liveCallStatePublisher
            .sink { [weak self] liveCallState in
                self?.handleLiveCallUpdate(liveCallState)
            }
        settingsSubscription = settingsStore.settingsPublisher
            .sink { [weak self] settings in
                self?.hapticFeedbackEnabled = settings.voice.hapticFeedback
                self?.showsActionDetail = settings.display.showsActionDetail
            }
        let loadedSettings = settingsStore.load()
        hapticFeedbackEnabled = loadedSettings.voice.hapticFeedback
        showsActionDetail = loadedSettings.display.showsActionDetail
    }

    convenience init(dependencies: AppDependencies) {
        self.init(
            workspaces: dependencies.workspaces,
            boards: dependencies.boards,
            actions: dependencies.actions,
            callService: dependencies.callService,
            history: dependencies.history,
            calledMarkers: dependencies.calledMarkers,
            settingsStore: dependencies.settingsStore
        )
    }

    var isCallActive: Bool {
        switch liveCall.phase {
        case .queued, .preparing, .playingPrompt, .speaking:
            return true
        case .idle, .completed, .cancelled, .interrupted, .failed:
            return false
        }
    }

    /// The number of actions on the current board that have already been
    /// called. Scoped to the board so the progress always reflects what the
    /// operator is looking at.
    var calledCount: Int {
        guard case .loaded(let content) = state else {
            return 0
        }
        return content.actions.count { calledActionIDs.contains($0.id) }
    }

    /// The total number of actions on the current board — the denominator
    /// for the progress overview.
    var totalCount: Int {
        guard case .loaded(let content) = state else {
            return 0
        }
        return content.actions.count
    }

    /// How many calls are waiting in the queue behind the running one. The
    /// pending set includes the active call itself, so that one is not
    /// counted as waiting while a call is in flight.
    var queuedCallCount: Int {
        max(0, pendingActionIDs.count - (isCallActive ? 1 : 0))
    }

    func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }
        await load()
    }

    func load() async {
        hasLoaded = true
        state = .loading
        // Restore which tiles were already announced on a previous run so a
        // fresh session does not lose the called progress. Opening the app
        // on a new day yields an empty set, so yesterday's markers drop
        // here automatically.
        calledActionIDs = calledMarkers.load()
        await restoreLastCompletedCall()
        await reloadContent()
        scheduleMidnightResetIfNeeded()
    }

    /// Restores the undo target from persisted history so a relaunch keeps
    /// the long-press undo working without requiring a new call first.
    private func restoreLastCompletedCall() async {
        guard let filter = try? CallHistoryFilter(results: [.completed], limit: 1) else {
            os_log(.error, log: Self.log, "undo-restore: failed to build history filter")
            return
        }
        let records: [CallRecord]
        do {
            records = try await history.fetch(filter)
        } catch {
            os_log(.error, log: Self.log, "undo-restore: history.fetch failed: %{public}@", "\(error)")
            return
        }
        guard let record = records.first else {
            os_log(.info, log: Self.log, "undo-restore: history has no completed records")
            return
        }
        guard let actionID = record.actionID else {
            os_log(.info, log: Self.log, "undo-restore: latest record is detached (no actionID)")
            return
        }
        lastCalledActionID = actionID
        lastCompletedRecordID = record.id
        os_log(.info, log: Self.log, "undo-restore: restored lastCalledActionID=%{public}@", actionID.uuidString)
    }

    private nonisolated static let log = OSLog(subsystem: "io.wayneho.CallDesk", category: "UndoRestore")

    /// Reloads data without flashing the loading state, so returning to the
    /// tab picks up board and action changes made on the Boards tab.
    func refresh() async {
        guard hasLoaded else {
            await load()
            return
        }
        // The store drops markers recorded on a previous day, so coming
        // back on a new business day starts the panel clean.
        syncCalledMarkers()
        scheduleMidnightResetIfNeeded()
        await reloadContent()
    }

    /// Re-reads the persisted markers; a day rollover clears them.
    func syncCalledMarkers() {
        calledActionIDs = calledMarkers.load()
    }

    /// Keeps the panel clean while the app stays open across midnight:
    /// one task sleeps until the next day boundary, resets the markers,
    /// and reschedules itself for the following night. It only holds the
    /// view model weakly, so releasing the view model lets the loop end
    /// on its own next wake-up.
    private func scheduleMidnightResetIfNeeded() {
        guard midnightResetTask == nil else {
            return
        }
        midnightResetTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                guard let nextMidnight = self.nextMidnight() else {
                    return
                }
                try? await Task.sleep(for: .seconds(max(1, nextMidnight.timeIntervalSince(self.currentDate()))))
                guard !Task.isCancelled else {
                    return
                }
                self.performDailyReset()
            }
        }
    }

    /// Clears the called tints the moment a new day starts while the app
    /// is running, so the operator never has to reset by hand.
    private func performDailyReset() {
        calledActionIDs.removeAll()
        calledMarkers.save([])
        lastCalledActionID = nil
        lastCompletedRecordID = nil
    }

    private func nextMidnight() -> Date? {
        calendar.nextDate(
            after: now(),
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        )
    }

    private func currentDate() -> Date {
        now()
    }

    private func reloadContent() async {
        do {
            guard let workspace = try await workspaces.fetchAll().first else {
                state = .empty
                return
            }
            let visibleBoards = try await boards.fetchAll(
                workspaceID: workspace.id,
                includeArchived: false
            )
            guard let firstBoard = visibleBoards.first else {
                state = .empty
                return
            }
            let selectedBoardID = retainedSelectedBoardID(in: visibleBoards) ?? firstBoard.id
            let boardActions = try await actions.fetch(
                boardID: selectedBoardID,
                includeDisabled: true
            )
            state = .loaded(
                Content(
                    workspaceName: workspace.name,
                    boards: visibleBoards,
                    selectedBoardID: selectedBoardID,
                    actions: boardActions
                )
            )
        } catch {
            state = .failed
        }
    }

    /// Keeps the user's board selection across refreshes while the board
    /// still exists; otherwise selection falls back to the first board.
    private func retainedSelectedBoardID(in visibleBoards: [CallBoard]) -> UUID? {
        guard case .loaded(let content) = state,
              visibleBoards.contains(where: { $0.id == content.selectedBoardID }) else {
            return nil
        }
        return content.selectedBoardID
    }

    func selectBoard(id: UUID) async {
        guard case .loaded(let content) = state,
              content.selectedBoardID != id,
              content.boards.contains(where: { $0.id == id }) else {
            return
        }

        // The keyboard selection belongs to a board's tiles; it must not
        // leak onto the next board's grid.
        selectedActionID = nil

        do {
            let boardActions = try await actions.fetch(boardID: id, includeDisabled: true)
            state = .loaded(
                Content(
                    workspaceName: content.workspaceName,
                    boards: content.boards,
                    selectedBoardID: id,
                    actions: boardActions
                )
            )
        } catch {
            state = .failed
        }
    }

    /// Whether the given action has been called in the current session.
    func hasBeenCalled(actionID: UUID) -> Bool {
        calledActionIDs.contains(actionID)
    }

    /// Whether the given action is running or waiting in the queue.
    func isPending(actionID: UUID) -> Bool {
        pendingActionIDs.contains(actionID)
    }

    /// Whether the given called action is eligible for long-press undo.
    /// Only the called action with the highest sort order on the current
    /// board can be undone, so the operator works backwards from the
    /// largest number (e.g. undo #8, then #7, then #6 …).
    func isUndoable(actionID: UUID) -> Bool {
        guard case .loaded(let content) = state,
              calledActionIDs.contains(actionID) else {
            return false
        }
        let calledActions = content.actions.filter { calledActionIDs.contains($0.id) }
        guard let maxSortAction = calledActions.max(by: { $0.sortOrder < $1.sortOrder }) else {
            return false
        }
        return maxSortAction.id == actionID
    }

    /// Clears the called-tint state so every tile returns to its default
    /// look. Useful when the operator wants to start the same board over.
    /// Persisted markers are cleared too, so the reset survives a relaunch.
    func resetCalledActions() {
        calledActionIDs.removeAll()
        calledMarkers.save([])
    }

    /// Removes today's completed history records of a completed call for
    /// the given action and un-marks its tile, so an accidental call stops
    /// counting. All of today's records for the number are deleted at once,
    /// because one accidental tap can produce several completed records and
    /// the daily count (the max reached number) only drops once every one
    /// of them is gone.
    func undoCall(for actionID: UUID) async {
        guard calledActionIDs.contains(actionID) else {
            return
        }
        let recordIDs = await todayCompletedRecordIDs(for: actionID)
        guard !recordIDs.isEmpty else {
            undoFailed = true
            return
        }
        do {
            try await history.delete(ids: recordIDs)
        } catch {
            undoFailed = true
            return
        }
        calledActionIDs.remove(actionID)
        calledMarkers.save(calledActionIDs)
        if lastCalledActionID == actionID {
            self.lastCalledActionID = nil
            self.lastCompletedRecordID = nil
        }
    }

    /// Every completed history record of the given action that started
    /// today; a repeated accidental tap produces one record per call.
    private func todayCompletedRecordIDs(for actionID: UUID) async -> Set<UUID> {
        let todayStart = Calendar.current.startOfDay(for: Date())
        guard let filter = try? CallHistoryFilter(
            startedFrom: todayStart,
            actionID: actionID,
            results: [.completed]
        ) else {
            return []
        }
        guard let records = try? await history.fetch(filter) else {
            return []
        }
        return Set(records.map(\.id))
    }

    /// Dismisses the undo-failure message.
    func dismissUndoFailure() {
        undoFailed = false
    }

    /// Dismisses the failure banner without waiting for the next call.
    func dismissCallFailure() {
        callOutcomeFailure = nil
    }

    /// Moves the keyboard selection to the next enabled action, wrapping
    /// around to the first one.
    func selectNextAction() {
        moveSelection(by: 1)
    }

    /// Moves the keyboard selection to the previous enabled action, wrapping
    /// around to the last one.
    func selectPreviousAction() {
        moveSelection(by: -1)
    }

    /// Triggers the call for the keyboard-selected action, if any.
    func callSelectedAction() async {
        guard let selectedActionID else {
            return
        }
        await callAction(id: selectedActionID)
    }

    /// The enabled actions of the current board in display order — the pool
    /// the keyboard selection cycles through.
    private var selectableActions: [CallAction] {
        guard case .loaded(let content) = state else {
            return []
        }
        return content.actions.filter(\.isEnabled)
    }

    private func moveSelection(by offset: Int) {
        let selectable = selectableActions
        guard !selectable.isEmpty else {
            selectedActionID = nil
            return
        }
        guard let currentIndex = selectable.firstIndex(where: { $0.id == selectedActionID }) else {
            selectedActionID = offset > 0 ? selectable.first?.id : selectable.last?.id
            return
        }
        let nextIndex = (currentIndex + offset + selectable.count) % selectable.count
        selectedActionID = selectable[nextIndex].id
    }

    func callAction(id: UUID) async {
        guard case .loaded(let content) = state,
              let action = content.actions.first(where: { $0.id == id }),
              action.isEnabled else {
            return
        }

        // Tapping a pending tile again cancels that request so the color
        // reverts; the operator might have tapped it by accident. The tile
        // reverts immediately; the authoritative set is refreshed after
        // the cancellation completes.
        if isPending(actionID: id) {
            pendingActionIDs.remove(id)
            isCancellingPendingAction = true
            defer { isCancellingPendingAction = false }
            await callService.cancelPendingAction(actionID: id)
            refreshPendingActionIDs()
            return
        }

        // A finished tile is re-callable: tapping it again starts a fresh
        // call, so a busy operator can re-announce a number on demand. The
        // tile is marked requested immediately so the touch registers
        // before the request finishes announcing.
        pendingActionIDs.insert(action.id)
        await callService.requestCall(
            CallingRequest(actionID: action.id, boardID: action.boardID)
        )
        refreshPendingActionIDs()
    }

    func cancelActiveCall() async {
        await callService.cancelActiveCall()
        refreshPendingActionIDs()
    }

    /// Mirrors the service state unless a cancellation is in flight; the
    /// service cleans up cancelled sessions asynchronously, so reading it
    /// mid-cancellation would resurrect tiles that already reverted.
    private func refreshPendingActionIDs() {
        guard !isCancellingPendingAction else {
            return
        }
        pendingActionIDs = callService.pendingActionIDs
    }

    /// Tracks the live-call publisher and flips the called-tint on the
    /// moment a call transitions from "active" to "terminal" (completed or
    /// cancelled). Idle/queued updates only refresh the published state.
    private func handleLiveCallUpdate(_ newState: LiveCallState) {
        let previousID = lastActiveActionID
        liveCall = newState
        refreshPendingActionIDs()

        switch newState.phase {
        case .queued, .preparing, .playingPrompt, .speaking:
            // A call is in flight — remember its ID so we can mark it
            // called when it finishes, and clear any earlier failure since
            // the operator has moved on to a new announcement.
            callOutcomeFailure = nil
            lastActiveActionID = newState.actionID
        case .completed:
            if let previousID {
                calledActionIDs.insert(previousID)
                calledMarkers.save(calledActionIDs)
                lastCalledActionID = previousID
                lastCompletedRecordID = callService.lastCompletedCallRecordID
            }
            lastActiveActionID = nil
        case .interrupted:
            // A system interruption took the output away; the operator must
            // know the announcement did not go out.
            callOutcomeFailure = .interrupted
            lastActiveActionID = nil
        case .failed(let message):
            // Speech playback failed; the tile stays un-called so it can be
            // retried.
            callOutcomeFailure = .failed(message)
            lastActiveActionID = nil
        case .idle, .cancelled:
            // Terminal states without a successful completion don't mark
            // the tile as called.
            lastActiveActionID = nil
        }
    }
}
