import Foundation
import Testing
@testable import CallDesk

@Suite("Call board domain model")
struct CallBoardTests {
    private let workspaceID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private let createdAt = Date(timeIntervalSinceReferenceDate: 100)

    private let boardID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    @Test("Initializer trims a board name")
    func initializerTrimsName() throws {
        let board = try CallBoard(
            id: boardID,
            workspaceID: workspaceID,
            name: "  Reception  ",
            sortOrder: 0,
            createdAt: createdAt
        )

        #expect(board.name == "Reception")
    }

    @Test("Initializer rejects an empty board name")
    func boardInitializerRejectsEmptyName() {
        #expect(throws: DomainValidationError.emptyName(field: "name")) {
            try CallBoard(
                id: boardID,
                workspaceID: workspaceID,
                name: " \t ",
                sortOrder: 0,
                createdAt: createdAt
            )
        }
    }

    @Test("Initializer normalizes a blank subtitle to nil")
    func initializerNormalizesBlankSubtitle() throws {
        let board = try CallBoard(
            id: boardID,
            workspaceID: workspaceID,
            name: "Reception",
            subtitle: "  \n ",
            sortOrder: 0,
            createdAt: createdAt
        )

        #expect(board.subtitle == nil)
    }

    @Test("Initializer accepts preferred column counts from two through eight", arguments: 2...8)
    func initializerAcceptsLegalColumnCount(columnCount: Int) throws {
        let board = try CallBoard(
            id: boardID,
            workspaceID: workspaceID,
            name: "Reception",
            sortOrder: 0,
            preferredColumnCount: columnCount,
            createdAt: createdAt
        )

        #expect(board.preferredColumnCount == columnCount)
    }

    @Test("Initializer rejects illegal preferred column counts", arguments: [1, 9])
    func initializerRejectsIllegalColumnCount(columnCount: Int) {
        #expect(throws: DomainValidationError.invalidColumnCount) {
            try CallBoard(
                id: boardID,
                workspaceID: workspaceID,
                name: "Reception",
                sortOrder: 0,
                preferredColumnCount: columnCount,
                createdAt: createdAt
            )
        }
    }

    @Test("Initializer rejects a negative board sort order")
    func boardInitializerRejectsNegativeSortOrder() {
        #expect(throws: DomainValidationError.invalidSortOrder) {
            try CallBoard(
                id: boardID,
                workspaceID: workspaceID,
                name: "Reception",
                sortOrder: -1,
                createdAt: createdAt
            )
        }
    }

    @Test("Board initializer rejects an update date before the creation date")
    func boardInitializerRejectsUpdateDateBeforeCreationDate() {
        #expect(throws: DomainValidationError.invalidDateRange) {
            try CallBoard(
                id: boardID,
                workspaceID: workspaceID,
                name: "Reception",
                sortOrder: 0,
                createdAt: createdAt,
                updatedAt: Date(timeIntervalSinceReferenceDate: 50)
            )
        }
    }

    @Test("Initializer defaults a board to show recent calls and remain active")
    func initializerDefaultsToShowingRecentCallsAndActive() throws {
        let board = try CallBoard(
            id: boardID,
            workspaceID: workspaceID,
            name: "Reception",
            sortOrder: 0,
            createdAt: createdAt
        )

        #expect(board.showsRecentCalls == true)
        #expect(board.isArchived == false)
        #expect(board.preferredColumnCount == nil)
    }
}
