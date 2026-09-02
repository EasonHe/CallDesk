import Combine
import Foundation

/// The default calling flow coordinator.
///
/// The service is `MainActor` isolated, which keeps every state mutation
/// thread safe while repositories and the speech driver do their work
/// asynchronously. Sessions run strictly one after another; concurrent
/// requests are resolved with the configured `ActiveSpeechPolicy`.
@MainActor
final class DefaultCallService: CallService {
    private enum TerminationReason {
        case cancelled
        case interrupted
    }

    /// Everything one session announces and records, whether it comes from
    /// a live `CallAction` or from a history snapshot during a recall.
    private struct SessionContent {
        let actionID: UUID?
        let boardID: UUID?
        let title: String
        let speechText: String
        let audioFileName: String?
    }

    private(set) var liveCallState: LiveCallState = .idle {
        didSet {
            liveCallStateSubject.send(liveCallState)
        }
    }

    private(set) var activeSession: CallingSession?

    /// The number of sessions that are running or waiting in the queue.
    var pendingCallCount: Int {
        sessionTasks.count
    }

    /// The action IDs that are running or waiting in the queue.
    var pendingActionIDs: Set<UUID> {
        Set(sessionRequests.values.map(\.actionID))
    }

    private(set) var lastCompletedCallRecordID: UUID?

    var liveCallStatePublisher: AnyPublisher<LiveCallState, Never> {
        liveCallStateSubject.eraseToAnyPublisher()
    }

    private let actions: any CallActionRepository
    private let history: any CallHistoryRepository
    private let settingsStore: any SettingsStore
    private let speechDriver: any CallSpeechDriving
    private let audioClips: any AudioClipStoring
    private let audioEnvironment: any AudioEnvironmentMonitoring
    private let now: @Sendable () -> Date

    private let liveCallStateSubject = CurrentValueSubject<LiveCallState, Never>(.idle)
    private var sessionTasks: [UUID: Task<CallingResult, Never>] = [:]
    /// The request behind every session, keyed by session ID; used to
    /// report which action IDs are still running or waiting in the queue.
    private var sessionRequests: [UUID: CallingRequest] = [:]
    private var terminationReasons: [UUID: TerminationReason] = [:]
    private var latestSessionID: UUID?
    private var latestCompletion: SessionCompletion?
    private var interruptionSubscription: AnyCancellable?

    init(
        actions: any CallActionRepository,
        history: any CallHistoryRepository,
        settingsStore: any SettingsStore = InMemorySettingsStore(),
        speechDriver: any CallSpeechDriving = SilentCallSpeechDriver(),
        audioClips: any AudioClipStoring = FileSystemAudioClipStore(),
        audioEnvironment: any AudioEnvironmentMonitoring = FixedAudioEnvironmentMonitor(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.actions = actions
        self.history = history
        self.settingsStore = settingsStore
        self.speechDriver = speechDriver
        self.audioClips = audioClips
        self.audioEnvironment = audioEnvironment
        self.now = now
        // A system interruption (an incoming phone call, another app
        // claiming the output) ends the running session as interrupted.
        // Nothing resumes automatically when the interruption ends: the
        // session activates per utterance, so the next call recovers the
        // audio session on its own.
        interruptionSubscription = audioEnvironment.interruptionPublisher
            .sink { [weak self] event in
                if case .began = event {
                    self?.terminateUnfinishedSessions(reason: .interrupted)
                }
            }
    }

    @discardableResult
    func requestCall(_ request: CallingRequest) async -> CallingResult {
        guard admitNewSession() else {
            return .ignored
        }
        return await enqueueSession(request: request) { [weak self] sessionID in
            guard let self else {
                return .cancelled
            }
            return await self.runSession(id: sessionID, request: request)
        }
    }

    @discardableResult
    func requestRecall(from record: CallRecord) async -> CallingResult {
        guard admitNewSession() else {
            return .ignored
        }
        var request: CallingRequest?
        if let actionID = record.actionID, let boardID = record.boardID {
            request = CallingRequest(actionID: actionID, boardID: boardID)
        }
        return await enqueueSession(request: request) { [weak self] sessionID in
            guard let self else {
                return .cancelled
            }
            return await self.runRecallSession(id: sessionID, record: record)
        }
    }

    /// Applies the active speech policy to a new request.
    /// Returns `false` when the request must be ignored.
    private func admitNewSession() -> Bool {
        guard !sessionTasks.isEmpty else {
            return true
        }
        // Concurrent requests are resolved with the policy that is
        // configured right now, not the one from app launch.
        switch settingsStore.load().calling.activeSpeechPolicy {
        case .ignoreNewCall:
            return false
        case .interruptCurrent:
            terminateUnfinishedSessions(reason: .interrupted)
            return true
        case .queueNext:
            return true
        }
    }

    private func enqueueSession(
        request: CallingRequest?,
        _ body: @escaping @MainActor (UUID) async -> CallingResult
    ) async -> CallingResult {
        let sessionID = UUID()
        if let request {
            sessionRequests[sessionID] = request
        }
        let predecessorCompletion = latestCompletion
        let completion = SessionCompletion()
        let sessionTask = Task { () -> CallingResult in
            if let predecessorCompletion {
                // Queue slots park until the session ahead finishes, but
                // a slot cancelled while parked must leave right away:
                // the cancel APIs await this task, so staying behind a
                // running session would hang them.
                await withTaskCancellationHandler {
                    await predecessorCompletion.wait()
                } onCancel: {
                    Task { @MainActor in
                        predecessorCompletion.cancelWaiter()
                    }
                }
            }
            return await body(sessionID)
        }
        sessionTasks[sessionID] = sessionTask
        latestSessionID = sessionID
        latestCompletion = completion

        let result = await sessionTask.value
        sessionTasks[sessionID] = nil
        sessionRequests[sessionID] = nil
        terminationReasons[sessionID] = nil
        // Clear the bookkeeping before waking the queued slot: from the
        // moment the completion fires, this session must be fully gone.
        completion.markFinished()
        if latestSessionID == sessionID {
            latestSessionID = nil
            latestCompletion = nil
        }
        return result
    }

    func cancelActiveCall() async {
        guard !sessionTasks.isEmpty else {
            return
        }

        let unfinishedTasks = Array(sessionTasks.values)
        terminateUnfinishedSessions(reason: .cancelled)
        for task in unfinishedTasks {
            _ = await task.value
            // `enqueueSession` also awaits the task and removes its session
            // entry afterwards; yield so that cleanup runs before returning,
            // keeping `pendingCallCount` accurate to the caller.
            await Task.yield()
        }
    }

    func cancelPendingAction(actionID: UUID) async {
        let matchingSessionIDs = sessionRequests
            .filter { $0.value.actionID == actionID }
            .map(\.key)
        guard !matchingSessionIDs.isEmpty else {
            return
        }

        let tasks = matchingSessionIDs.compactMap { sessionTasks[$0] }
        for sessionID in matchingSessionIDs where terminationReasons[sessionID] == nil {
            terminationReasons[sessionID] = .cancelled
        }
        for task in tasks {
            task.cancel()
        }
        for task in tasks {
            _ = await task.value
            // Same cleanup ordering as `cancelActiveCall`: the session is
            // only fully gone once `enqueueSession` finished its bookkeeping.
            await Task.yield()
        }
    }

    // MARK: - Session lifecycle

    private func runSession(id sessionID: UUID, request: CallingRequest) async -> CallingResult {
        if Task.isCancelled {
            // The session was discarded before it started; nothing was
            // announced, so no state change or history entry is needed.
            resetToIdleIfLatest(sessionID)
            return terminationResult(for: sessionID)
        }

        // The session snapshot: taken when the session actually starts, so
        // the next call always uses the latest saved settings while a
        // running session is never affected by mid-session changes.
        let settings = settingsStore.load()
        let startedAt = now()
        activeSession = CallingSession(id: sessionID, request: request, startedAt: startedAt)
        defer {
            if activeSession?.id == sessionID {
                activeSession = nil
            }
        }

        emit(
            phase: .preparing,
            actionID: request.actionID,
            boardID: request.boardID,
            repeatIndex: 0,
            startedAt: startedAt
        )

        let action: CallAction
        do {
            guard let loadedAction = try await actions.action(id: request.actionID) else {
                return finishWithoutHistory(
                    sessionID: sessionID,
                    request: request,
                    startedAt: startedAt,
                    message: "The action no longer exists."
                )
            }
            action = loadedAction
        } catch {
            return finishWithoutHistory(
                sessionID: sessionID,
                request: request,
                startedAt: startedAt,
                message: "The action could not be loaded."
            )
        }

        let content = SessionContent(
            actionID: action.id,
            boardID: action.boardID,
            title: action.title,
            speechText: action.speechText,
            audioFileName: action.playbackMode == .audio ? action.audioFileName : nil
        )

        guard action.isEnabled else {
            let message = "The action is disabled."
            emit(phase: .failed(message: message), content: content, repeatIndex: 0, startedAt: startedAt)
            await saveRecord(
                content: content,
                startedAt: startedAt,
                repeatIndex: 0,
                result: .failed,
                errorDescription: message
            )
            resetToIdleIfLatest(sessionID)
            return .failed(message: message)
        }

        return await announce(
            sessionID: sessionID,
            content: content,
            settings: settings,
            startedAt: startedAt
        )
    }

    /// Replays a history snapshot without touching the original action.
    ///
    /// The stored snapshot is the source of truth: no action lookup and no
    /// enabled check happen here, so the recall keeps working after the
    /// original action, board, or scene has been deleted or edited.
    private func runRecallSession(id sessionID: UUID, record: CallRecord) async -> CallingResult {
        if Task.isCancelled {
            resetToIdleIfLatest(sessionID)
            return terminationResult(for: sessionID)
        }

        let settings = settingsStore.load()
        let startedAt = now()
        // `CallingRequest` requires both identifiers, so the active session
        // is only surfaced when the snapshot still carries them.
        if let actionID = record.actionID, let boardID = record.boardID {
            activeSession = CallingSession(
                id: sessionID,
                request: CallingRequest(actionID: actionID, boardID: boardID),
                startedAt: startedAt
            )
        }
        defer {
            if activeSession?.id == sessionID {
                activeSession = nil
            }
        }

        let content = SessionContent(
            actionID: record.actionID,
            boardID: record.boardID,
            title: record.actionTitleSnapshot,
            speechText: record.spokenTextSnapshot,
            audioFileName: record.audioFileNameSnapshot
        )

        emit(phase: .preparing, content: content, repeatIndex: 0, startedAt: startedAt)

        return await announce(
            sessionID: sessionID,
            content: content,
            settings: settings,
            startedAt: startedAt
        )
    }

    /// The shared announcement loop: speaks the content with the given
    /// settings snapshot, writes one history record, and resets the live
    /// state. Used by regular calls and recalls alike.
    private func announce(
        sessionID: UUID,
        content: SessionContent,
        settings: CallDeskSettings,
        startedAt: Date
    ) async -> CallingResult {
        var repeatIndex = 0
        do {
            let repeatCount = settings.calling.defaultRepeatCount
            while true {
                try Task.checkCancellation()
                emit(phase: .speaking, content: content, repeatIndex: repeatIndex, startedAt: startedAt)
                try await speechDriver.announce(
                    makeAnnouncement(for: content),
                    voice: settings.voice,
                    promptTone: settings.promptTone
                )
                if repeatIndex >= repeatCount {
                    break
                }
                repeatIndex += 1
                if settings.calling.repeatDelay > 0 {
                    try await Task.sleep(nanoseconds: UInt64(settings.calling.repeatDelay * 1_000_000_000))
                }
            }
        } catch is CancellationError {
            let result = terminationResult(for: sessionID)
            let phase: LiveCallPhase = result == .interrupted ? .interrupted : .cancelled
            // A session ending behind a newer one must not overwrite the
            // live state: the termination phases race when several
            // sessions end at once, and only the latest one is visible.
            if latestSessionID == sessionID {
                emit(phase: phase, content: content, repeatIndex: repeatIndex, startedAt: startedAt)
            }
            await saveRecord(
                content: content,
                startedAt: startedAt,
                repeatIndex: repeatIndex,
                result: result == .interrupted ? .interrupted : .cancelled,
                errorDescription: nil
            )
            resetToIdleIfLatest(sessionID)
            return result
        } catch {
            let message = "Speech playback failed."
            emit(phase: .failed(message: message), content: content, repeatIndex: repeatIndex, startedAt: startedAt)
            await saveRecord(
                content: content,
                startedAt: startedAt,
                repeatIndex: repeatIndex,
                result: .failed,
                errorDescription: message
            )
            resetToIdleIfLatest(sessionID)
            return .failed(message: message)
        }

        emit(phase: .completed, content: content, repeatIndex: repeatIndex, startedAt: startedAt)
        await saveRecord(
            content: content,
            startedAt: startedAt,
            repeatIndex: repeatIndex,
            result: .completed,
            errorDescription: nil
        )
        resetToIdleIfLatest(sessionID)
        return .completed
    }

    private func finishWithoutHistory(
        sessionID: UUID,
        request: CallingRequest,
        startedAt: Date,
        message: String
    ) -> CallingResult {
        // Without the action there is no valid snapshot for a history record.
        emit(
            phase: .failed(message: message),
            actionID: request.actionID,
            boardID: request.boardID,
            repeatIndex: 0,
            startedAt: startedAt
        )
        resetToIdleIfLatest(sessionID)
        return .failed(message: message)
    }

    // MARK: - Helpers

    /// Chooses what to play for a session: a stored audio clip when the
    /// content references one that still resolves on disk, otherwise the
    /// spoken text. Falling back to speech keeps a call working even if the
    /// clip file went missing.
    private func makeAnnouncement(for content: SessionContent) -> CallAnnouncement {
        if let name = content.audioFileName, let url = audioClips.url(forClipNamed: name) {
            return .audio(url)
        }
        return .speech(content.speechText)
    }

    private func terminateUnfinishedSessions(reason: TerminationReason) {
        for (sessionID, task) in sessionTasks {
            if terminationReasons[sessionID] == nil {
                terminationReasons[sessionID] = reason
            }
            task.cancel()
        }
    }

    private func terminationResult(for sessionID: UUID) -> CallingResult {
        terminationReasons[sessionID] == .interrupted ? .interrupted : .cancelled
    }

    private func emit(
        phase: LiveCallPhase,
        content: SessionContent,
        repeatIndex: Int,
        startedAt: Date
    ) {
        emit(
            phase: phase,
            actionID: content.actionID,
            boardID: content.boardID,
            title: content.title,
            spokenText: content.speechText,
            repeatIndex: repeatIndex,
            startedAt: startedAt
        )
    }

    private func emit(
        phase: LiveCallPhase,
        actionID: UUID?,
        boardID: UUID?,
        title: String? = nil,
        spokenText: String? = nil,
        repeatIndex: Int,
        startedAt: Date
    ) {
        let state = try? LiveCallState(
            actionID: actionID,
            boardID: boardID,
            title: title,
            spokenText: spokenText,
            phase: phase,
            repeatIndex: repeatIndex,
            startedAt: startedAt
        )
        liveCallState = state ?? .idle
    }

    private func resetToIdleIfLatest(_ sessionID: UUID) {
        if latestSessionID == sessionID {
            liveCallState = .idle
        }
    }

    private func saveRecord(
        content: SessionContent,
        startedAt: Date,
        repeatIndex: Int,
        result: CallResult,
        errorDescription: String?
    ) async {
        // `CallRecord` requires a non-empty spoken text snapshot; prompt-only
        // actions may not have one, so the title stands in for history.
        let spokenText = content.speechText.isEmpty ? content.title : content.speechText
        // The route that plays the announcement right now; recorded so the
        // history shows which device the call went out on.
        let audioRouteName = audioEnvironment.currentRoute.name
        func makeRecord(actionID: UUID?, boardID: UUID?) -> CallRecord? {
            try? CallRecord(
                actionID: actionID,
                boardID: boardID,
                actionTitleSnapshot: content.title,
                spokenTextSnapshot: spokenText,
                audioFileNameSnapshot: content.audioFileName,
                startedAt: startedAt,
                completedAt: max(now(), startedAt),
                result: result,
                repeatIndex: repeatIndex,
                audioRouteName: audioRouteName,
                errorDescription: errorDescription
            )
        }
        // History is best effort: a storage failure must not break the
        // calling flow that already happened.
        if let record = makeRecord(actionID: content.actionID, boardID: content.boardID) {
            do {
                try await history.save(record)
                if result == .completed {
                    lastCompletedCallRecordID = record.id
                }
            } catch RepositoryError.relationshipNotFound {
                // A recall can reference an action or board that was deleted
                // in the meantime. The record then degrades to a detached
                // snapshot: the announcement still shows up in history, just
                // without links to the removed business objects.
                if let detachedRecord = makeRecord(actionID: nil, boardID: nil) {
                    try? await history.save(detachedRecord)
                    if result == .completed {
                        lastCompletedCallRecordID = detachedRecord.id
                    }
                }
            } catch {
                // Ignored: the record cannot be written, the call still counts.
            }
        }
        await enforceHistoryRetention()
    }

    /// Applies the retention policy that is configured right now, so a
    /// settings change affects history handling from the very next call.
    /// A value of zero means the corresponding limit is disabled.
    private func enforceHistoryRetention() async {
        let historySettings = settingsStore.load().history
        guard let policy = try? HistoryRetentionPolicy(
            retentionDays: historySettings.retentionDays > 0 ? historySettings.retentionDays : nil,
            maximumRecordCount: historySettings.maximumRecordCount > 0 ? historySettings.maximumRecordCount : nil
        ), policy.retentionDays != nil || policy.maximumRecordCount != nil else {
            return
        }
        // Retention is best effort, like the history write itself.
        _ = try? await history.enforceRetention(policy, now: now())
    }
}

/// Tells a queued session when the session ahead of it finished. The
/// enqueue loop completes it once the session's task returns, which
/// wakes the parked slot immediately; cancellation also wakes the slot
/// so it never blocks behind a still-running predecessor.
@MainActor
private final class SessionCompletion {
    private(set) var isFinished = false
    private var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !isFinished else {
            return
        }
        await withCheckedContinuation { continuation in
            if Task.isCancelled {
                continuation.resume()
            } else {
                waiter = continuation
            }
        }
    }

    func markFinished() {
        isFinished = true
        resumeWaiter()
    }

    func cancelWaiter() {
        resumeWaiter()
    }

    private func resumeWaiter() {
        waiter?.resume()
        waiter = nil
    }
}
