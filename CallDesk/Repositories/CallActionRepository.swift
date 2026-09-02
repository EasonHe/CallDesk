import Foundation

nonisolated protocol CallActionRepository: Sendable {
    func fetch(boardID: UUID, includeDisabled: Bool) async throws -> [CallAction]
    func action(id: UUID) async throws -> CallAction?
    func save(_ action: CallAction) async throws
    func delete(id: UUID) async throws
    func reorder(boardID: UUID, orderedIDs: [UUID]) async throws
}
