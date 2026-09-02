import Foundation

struct InMemoryWorkspaceRepository: WorkspaceRepository {
    private let store: InMemoryCallDeskStore

    init(store: InMemoryCallDeskStore) {
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
