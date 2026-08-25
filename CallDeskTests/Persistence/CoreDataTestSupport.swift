import Foundation
@testable import CallDesk

/// Creates an isolated in-memory Core Data stack per test so nothing is ever
/// written to the user's disk.
nonisolated struct CoreDataTestContext {
    let persistence: PersistenceController
    let repositories: CoreDataRepositories

    init() {
        persistence = PersistenceController(inMemory: true)
        repositories = CoreDataRepositories(persistence: persistence)
    }

    /// Persists a workspace and one board inside it, returning the board ID.
    @discardableResult
    func makeBoard(workspaceValue: UInt8, boardValue: UInt8) async throws -> UUID {
        let workspaceID = coreDataFixedUUID(workspaceValue)
        let boardID = coreDataFixedUUID(boardValue)
        try await repositories.workspaces.save(try Workspace(id: workspaceID, name: "Workspace \(workspaceValue)"))
        try await repositories.boards.save(
            try CallBoard(id: boardID, workspaceID: workspaceID, name: "Board \(boardValue)", sortOrder: 0)
        )
        return boardID
    }
}

/// Deterministic identifiers shared by the Core Data repository tests.
nonisolated func coreDataFixedUUID(_ value: UInt8) -> UUID {
    UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
}
