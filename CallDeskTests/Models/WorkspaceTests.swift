import Foundation
import Testing
@testable import CallDesk

@Suite("Workspace domain model")
struct WorkspaceTests {
    private let workspaceID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let createdAt = Date(timeIntervalSinceReferenceDate: 100)
    private let renamedAt = Date(timeIntervalSinceReferenceDate: 200)

    @Test("Initializer trims a workspace name")
    func initializerTrimsName() throws {
        let workspace = try Workspace(
            id: workspaceID,
            name: "  Morning calls  ",
            createdAt: createdAt
        )

        #expect(workspace.id == workspaceID)
        #expect(workspace.name == "Morning calls")
        #expect(workspace.createdAt == createdAt)
        #expect(workspace.updatedAt == createdAt)
    }

    @Test("Initializer rejects an empty workspace name")
    func initializerRejectsEmptyName() {
        #expect(throws: DomainValidationError.emptyName(field: "name")) {
            try Workspace(id: workspaceID, name: " \n ", createdAt: createdAt)
        }
    }

    @Test("Initializer normalizes blank workspace notes to nil")
    func initializerNormalizesBlankNote() throws {
        let workspace = try Workspace(
            id: workspaceID,
            name: "Morning calls",
            note: "  \n  ",
            createdAt: createdAt
        )

        #expect(workspace.note == nil)
    }

    @Test("Initializer defaults a workspace to active")
    func initializerDefaultsToActive() throws {
        let workspace = try Workspace(id: workspaceID, name: "Morning calls", createdAt: createdAt)

        #expect(workspace.isArchived == false)
    }

    @Test("Initializer rejects an update date before the creation date")
    func initializerRejectsUpdateDateBeforeCreationDate() {
        #expect(throws: DomainValidationError.invalidDateRange) {
            try Workspace(
                id: workspaceID,
                name: "Morning calls",
                createdAt: createdAt,
                updatedAt: Date(timeIntervalSinceReferenceDate: 50)
            )
        }
    }

    @Test("Rename validates, trims, and updates the timestamp")
    func renameValidatesTrimsAndUpdatesTimestamp() throws {
        var workspace = try Workspace(id: workspaceID, name: "Morning calls", createdAt: createdAt)

        try workspace.rename(to: "  Afternoon calls  ", at: renamedAt)

        #expect(workspace.name == "Afternoon calls")
        #expect(workspace.updatedAt == renamedAt)
    }
}
