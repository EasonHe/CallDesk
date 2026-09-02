import Foundation
import Testing
@testable import CallDesk

@Suite("Core Data call action repository")
struct CoreDataCallActionRepositoryTests {
    @Test("Fetch filters disabled actions and orders by sortOrder then identifier")
    func fetchFiltersAndOrders() async throws {
        let context = CoreDataTestContext()
        let boardID = try await context.makeBoard(workspaceValue: 1, boardValue: 2)
        let actions = context.repositories.actions
        try await actions.save(
            try CallAction(id: coreDataFixedUUID(4), boardID: boardID, title: "Tied B", speechText: "B", sortOrder: 1)
        )
        try await actions.save(
            try CallAction(id: coreDataFixedUUID(3), boardID: boardID, title: "Tied A", speechText: "A", sortOrder: 1)
        )
        try await actions.save(
            try CallAction(
                id: coreDataFixedUUID(5),
                boardID: boardID,
                title: "Disabled",
                speechText: "Off",
                sortOrder: 0,
                isEnabled: false
            )
        )

        let enabled = try await actions.fetch(boardID: boardID, includeDisabled: false)
        #expect(enabled.map(\.id) == [coreDataFixedUUID(3), coreDataFixedUUID(4)])

        let all = try await actions.fetch(boardID: boardID, includeDisabled: true)
        #expect(all.map(\.id) == [coreDataFixedUUID(5), coreDataFixedUUID(3), coreDataFixedUUID(4)])
    }

    @Test("Round-trips every field including enums and optional values")
    func roundTripsEveryField() async throws {
        let context = CoreDataTestContext()
        let boardID = try await context.makeBoard(workspaceValue: 6, boardValue: 7)
        let templateID = coreDataFixedUUID(8)
        try await context.repositories.templates.save(
            try VoiceTemplate(id: templateID, name: "Queue", templateText: "Call {number}", localeIdentifier: "en_US")
        )
        let createdAt = Date(timeIntervalSince1970: 5_000)
        let action = try CallAction(
            id: coreDataFixedUUID(9),
            boardID: boardID,
            title: "A001",
            speechText: "Number A001 to window 3",
            type: .queueNumber,
            voiceTemplateID: templateID,
            sortOrder: 4,
            style: .warning,
            promptToneEnabled: false,
            storesInRecentCalls: false,
            isEnabled: false,
            createdAt: createdAt,
            updatedAt: createdAt.addingTimeInterval(30)
        )

        try await context.repositories.actions.save(action)
        #expect(try await context.repositories.actions.action(id: action.id) == action)
    }

    @Test("Save validates board, template reference, and fixed board")
    func saveValidatesRelationships() async throws {
        let context = CoreDataTestContext()
        let missingBoardID = coreDataFixedUUID(10)
        let actionID = coreDataFixedUUID(11)
        let actions = context.repositories.actions

        await #expect(throws: RepositoryError.relationshipNotFound(entity: "CallBoard", id: missingBoardID)) {
            try await actions.save(
                try CallAction(id: actionID, boardID: missingBoardID, title: "A001", speechText: "A001")
            )
        }

        let boardID = try await context.makeBoard(workspaceValue: 12, boardValue: 13)
        let otherBoardID = try await context.makeBoard(workspaceValue: 14, boardValue: 15)
        let missingTemplateID = coreDataFixedUUID(16)

        await #expect(
            throws: RepositoryError.relationshipNotFound(entity: "VoiceTemplate", id: missingTemplateID)
        ) {
            try await actions.save(
                try CallAction(
                    id: actionID,
                    boardID: boardID,
                    title: "A001",
                    speechText: "A001",
                    voiceTemplateID: missingTemplateID
                )
            )
        }

        try await actions.save(try CallAction(id: actionID, boardID: boardID, title: "A001", speechText: "A001"))
        await #expect(
            throws: RepositoryError.relationshipConflict(message: "Action board cannot be changed.")
        ) {
            try await actions.save(
                try CallAction(id: actionID, boardID: otherBoardID, title: "A001", speechText: "A001")
            )
        }
    }

    @Test("Delete removes actions and missing identifiers are notFound")
    func deleteRemovesActions() async throws {
        let context = CoreDataTestContext()
        let boardID = try await context.makeBoard(workspaceValue: 17, boardValue: 18)
        let actionID = coreDataFixedUUID(19)
        try await context.repositories.actions.save(
            try CallAction(id: actionID, boardID: boardID, title: "A001", speechText: "A001")
        )

        try await context.repositories.actions.delete(id: actionID)
        #expect(try await context.repositories.actions.action(id: actionID) == nil)

        await #expect(throws: RepositoryError.notFound(entity: "CallAction", id: actionID)) {
            try await context.repositories.actions.delete(id: actionID)
        }
    }

    @Test("Reorder persists new positions and failures change nothing")
    func reorderSucceedsAndFailsAtomically() async throws {
        let context = CoreDataTestContext()
        let boardID = try await context.makeBoard(workspaceValue: 20, boardValue: 21)
        let actions = context.repositories.actions
        let firstID = coreDataFixedUUID(22)
        let secondID = coreDataFixedUUID(23)
        try await actions.save(
            try CallAction(id: firstID, boardID: boardID, title: "One", speechText: "One", sortOrder: 0)
        )
        try await actions.save(
            try CallAction(id: secondID, boardID: boardID, title: "Two", speechText: "Two", sortOrder: 1)
        )

        try await actions.reorder(boardID: boardID, orderedIDs: [secondID, firstID])
        let reordered = try await actions.fetch(boardID: boardID, includeDisabled: true)
        #expect(reordered.map(\.id) == [secondID, firstID])
        #expect(reordered.map(\.sortOrder) == [0, 1])

        await #expect(throws: RepositoryError.invalidReorder) {
            try await actions.reorder(boardID: boardID, orderedIDs: [firstID])
        }
        await #expect(throws: RepositoryError.relationshipNotFound(entity: "CallBoard", id: coreDataFixedUUID(24))) {
            try await actions.reorder(boardID: coreDataFixedUUID(24), orderedIDs: [firstID, secondID])
        }

        let unchanged = try await actions.fetch(boardID: boardID, includeDisabled: true)
        #expect(unchanged.map(\.id) == [secondID, firstID])
    }
}
