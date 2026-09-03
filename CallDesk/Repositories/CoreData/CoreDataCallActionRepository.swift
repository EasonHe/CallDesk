import Foundation

nonisolated struct CoreDataCallActionRepository: CallActionRepository {
    private let store: CoreDataCallDeskStore

    init(store: CoreDataCallDeskStore) {
        self.store = store
    }

    func fetch(boardID: UUID, includeDisabled: Bool) async throws -> [CallAction] {
        store.recordDiagnostic("ACTION-01 已进入叫号项仓库")
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
