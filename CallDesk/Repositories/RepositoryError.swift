import Foundation

nonisolated enum RepositoryError: Error, Equatable, Sendable {
    case notFound(entity: String, id: UUID)
    case duplicateIdentifier(entity: String, id: UUID)
    case relationshipNotFound(entity: String, id: UUID)
    case relationshipConflict(message: String)
    case invalidReorder
    case invalidQuery
    case configuredFailure(operation: String)
    case storageFailure(message: String)

    /// Passes repository errors through unchanged and converts any other
    /// error (such as a Core Data save failure) into a storage failure.
    init(wrapping error: any Error) {
        if let repositoryError = error as? RepositoryError {
            self = repositoryError
        } else {
            self = .storageFailure(message: String(describing: error))
        }
    }
}
