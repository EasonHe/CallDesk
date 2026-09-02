import Foundation

struct InMemoryCallActionRepository: CallActionRepository {
    private let store: InMemoryCallDeskStore

    init(store: InMemoryCallDeskStore) {
        self.store = store
    }

    func fetch(boardID: UUID, includeDisabled: Bool) async throws -> [CallAction] {
        try await store.fetchActions(boardID: boardID, includeDisabled: includeDisabled)
    }

    func action(id: UUID) async throws -> CallAction? {
        try await store.action(id: id)
    }

    func save(_ action: CallAction) async throws {
        try await store.saveAction(action)
    }

    func delete(id: UUID) async throws {
        try await store.deleteAction(id: id)
    }

    func reorder(boardID: UUID, orderedIDs: [UUID]) async throws {
        try await store.reorderActions(boardID: boardID, orderedIDs: orderedIDs)
    }
}
