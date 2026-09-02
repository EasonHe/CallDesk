import Foundation

/// A request to run one calling flow for a board action.
nonisolated struct CallingRequest: Equatable, Hashable, Sendable {
    let actionID: UUID
    let boardID: UUID

    init(actionID: UUID, boardID: UUID) {
        self.actionID = actionID
        self.boardID = boardID
    }
}
