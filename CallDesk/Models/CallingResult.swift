import Foundation

/// The terminal outcome of a calling request.
nonisolated enum CallingResult: Equatable, Sendable {
    /// The call finished all repeats.
    case completed
    /// The call was cancelled by the user.
    case cancelled
    /// The call was replaced by a newer request.
    case interrupted
    /// The request was rejected because another call was active.
    case ignored
    /// The call could not run or aborted with an error.
    case failed(message: String)
}
