import Foundation

nonisolated protocol WorkspaceRepository: Sendable {
    func fetchAll() async throws -> [Workspace]
    func workspace(id: UUID) async throws -> Workspace?
    func save(_ workspace: Workspace) async throws
    func delete(id: UUID) async throws
}
