import Foundation
import Testing
@testable import CallDesk

@Suite("Call action domain model")
struct CallActionTests {
    private let actionID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    private let boardID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
    private let date = Date(timeIntervalSinceReferenceDate: 100)

    @Test("Initializer trims a title and supplies semantic defaults")
    func initializerTrimsTitleAndSuppliesSemanticDefaults() throws {
        let action = try CallAction(
            id: actionID,
            boardID: boardID,
            title: "  A021  ",
            speechText: "  Please proceed to counter two.  ",
            now: date
        )

        #expect(action.id == actionID)
        #expect(action.boardID == boardID)
        #expect(action.title == "A021")
        #expect(action.speechText == "Please proceed to counter two.")
        #expect(action.type == .announcement)
        #expect(action.style == .standard)
    }

    @Test("Initializer rejects an empty title")
    func initializerRejectsEmptyTitle() {
        #expect(throws: DomainValidationError.emptyName(field: "title")) {
            try CallAction(
                id: actionID,
                boardID: boardID,
                title: " \n ",
                speechText: "Call A021",
                now: date
            )
        }
    }

    @Test("Prompt-only actions allow empty speech and default to enabled")
    func promptOnlyAllowsEmptySpeechAndDefaultsToEnabled() throws {
        let action = try CallAction(
            id: actionID,
            boardID: boardID,
            title: "  Alert  ",
            speechText: " \n ",
            type: .promptOnly,
            now: date
        )

        #expect(action.title == "Alert")
        #expect(action.speechText.isEmpty)
        #expect(action.promptToneEnabled == true)
        #expect(action.storesInRecentCalls == true)
        #expect(action.isEnabled == true)
    }

    @Test("Non-prompt actions reject blank speech")
    func nonPromptActionsRejectBlankSpeech() {
        #expect(throws: DomainValidationError.emptyText(field: "speechText")) {
            try CallAction(
                id: actionID,
                boardID: boardID,
                title: "A021",
                speechText: " \t ",
                now: date
            )
        }
    }

    @Test("Initializer rejects a negative sort order")
    func initializerRejectsNegativeSortOrder() {
        #expect(throws: DomainValidationError.invalidSortOrder) {
            try CallAction(
                id: actionID,
                boardID: boardID,
                title: "A021",
                speechText: "Call A021",
                sortOrder: -1,
                now: date
            )
        }
    }

    @Test("Initializer rejects an update date before its creation date")
    func initializerRejectsInvalidDateOrder() {
        #expect(throws: DomainValidationError.invalidDateRange) {
            try CallAction(
                id: actionID,
                boardID: boardID,
                title: "A021",
                speechText: "Call A021",
                createdAt: date,
                updatedAt: Date(timeIntervalSinceReferenceDate: 50)
            )
        }
    }
}
