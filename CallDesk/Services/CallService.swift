import Combine
import Foundation

/// Coordinates the calling flow for board actions.
///
/// The service owns the `LiveCallState` lifecycle
/// (idle → preparing → speaking → completed / cancelled / interrupted / failed),
/// writes one `CallRecord` per finished call, and resolves concurrent
/// requests with the active speech policy from `CallDeskSettings`.
@MainActor
protocol CallService: AnyObject {
    /// The current live call state. Starts and ends at `.idle`.
    var liveCallState: LiveCallState { get }

    /// Emits every live call state change, including the current value.
    var liveCallStatePublisher: AnyPublisher<LiveCallState, Never> { get }

    /// The session that is currently running, if any.
    var activeSession: CallingSession? { get }

    /// The action IDs that have been requested and not finished yet: the
    /// running call plus everything waiting in the queue.
    var pendingActionIDs: Set<UUID> { get }

    /// The id of the most recently saved completed call record, if any.
    var lastCompletedCallRecordID: UUID? { get }

    /// Runs one calling flow and returns its terminal result.
    @discardableResult
    func requestCall(_ request: CallingRequest) async -> CallingResult

    /// Replays a finished call from its history snapshot.
    ///
    /// The snapshot text is announced as it was saved, so a recall works
    /// even when the original action, board, or scene no longer exists.
    /// The recall writes a new history record and follows the same active
    /// speech policy as a regular call.
    @discardableResult
    func requestRecall(from record: CallRecord) async -> CallingResult

    /// Cancels the active call and discards queued requests.
    /// Returns once every affected session has finished.
    func cancelActiveCall() async

    /// Cancels the sessions for one action ID: the running call if it is
    /// for this action, plus its queued requests. Other calls keep running.
    /// Returns once the cancelled sessions have finished.
    func cancelPendingAction(actionID: UUID) async
}
