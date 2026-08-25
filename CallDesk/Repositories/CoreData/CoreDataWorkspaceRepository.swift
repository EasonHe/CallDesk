import Foundation

nonisolated struct CoreDataWorkspaceRepository: WorkspaceRepository {
    private let store: CoreDataCallDeskStore

    init(store: CoreDataCallDeskStore) {
        self.store = store
    }

    func fetchAll() async throws -> [Workspace] {
        try await store.fetchWorkspaces()
    }

    func workspace(id: UUID) async throws -> Workspace? {
        try await store.workspace(id: id)
    }

    func save(_ workspace: Workspace) async throws {
        try await store.saveWorkspace(workspace)
    }

    func delete(id: UUID) async throws {
        try await store.deleteWorkspace(id: id)
    }
}
