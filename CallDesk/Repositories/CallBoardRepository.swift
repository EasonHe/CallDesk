import Foundation

nonisolated protocol CallBoardRepository: Sendable {
    func fetchAll(workspaceID: UUID, includeArchived: Bool) async throws -> [CallBoard]
    func board(id: UUID) async throws -> CallBoard?
    func save(_ board: CallBoard) async throws
    func delete(id: UUID) async throws
    func reorder(workspaceID: UUID, orderedIDs: [UUID]) async throws
}
