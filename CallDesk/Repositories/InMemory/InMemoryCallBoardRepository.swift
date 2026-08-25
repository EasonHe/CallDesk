import Foundation

struct InMemoryCallBoardRepository: CallBoardRepository {
    private let store: InMemoryCallDeskStore

    init(store: InMemoryCallDeskStore) {
        self.store = store
    }

    func fetchAll(workspaceID: UUID, includeArchived: Bool) async throws -> [CallBoard] {
        try await store.fetchAllBoards(workspaceID: workspaceID, includeArchived: includeArchived)
    }

    func board(id: UUID) async throws -> CallBoard? {
        try await store.board(id: id)
    }

    func save(_ board: CallBoard) async throws {
        try await store.saveBoard(board)
    }

    func delete(id: UUID) async throws {
        try await store.deleteBoard(id: id)
    }

    func reorder(workspaceID: UUID, orderedIDs: [UUID]) async throws {
        try await store.reorderBoards(
            workspaceID: workspaceID,
            orderedIDs: orderedIDs
        )
    }
}
