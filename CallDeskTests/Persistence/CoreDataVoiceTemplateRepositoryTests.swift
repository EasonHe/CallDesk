import Foundation
import Testing
@testable import CallDesk

@Suite("Core Data voice template repository")
struct CoreDataVoiceTemplateRepositoryTests {
    @Test("Fetch filters built-in templates and orders by name then identifier")
    func fetchFiltersAndOrders() async throws {
        let context = CoreDataTestContext()
        let templates = context.repositories.templates
        try await templates.save(
            try VoiceTemplate(
                id: coreDataFixedUUID(1),
                name: "Built-in",
                templateText: "Number {number}",
                localeIdentifier: "en_US",
                isBuiltIn: true
            )
        )
        try await templates.save(
            try VoiceTemplate(id: coreDataFixedUUID(3), name: "Custom", templateText: "B", localeIdentifier: "en_US")
        )
        try await templates.save(
            try VoiceTemplate(id: coreDataFixedUUID(2), name: "Custom", templateText: "A", localeIdentifier: "en_US")
        )

        let custom = try await templates.fetchAll(includeBuiltIn: false)
        #expect(custom.map(\.id) == [coreDataFixedUUID(2), coreDataFixedUUID(3)])

        let all = try await templates.fetchAll(includeBuiltIn: true)
        #expect(all.map(\.id) == [coreDataFixedUUID(1), coreDataFixedUUID(2), coreDataFixedUUID(3)])
    }

    @Test("Round-trips fields and updates existing templates in place")
    func roundTripsAndUpdates() async throws {
        let context = CoreDataTestContext()
        let templates = context.repositories.templates
        let templateID = coreDataFixedUUID(4)
        let createdAt = Date(timeIntervalSince1970: 2_000)
        let template = try VoiceTemplate(
            id: templateID,
            name: "Queue",
            templateText: "Number {number} to {counter}",
            localeIdentifier: "zh_CN",
            createdAt: createdAt,
            updatedAt: createdAt.addingTimeInterval(15)
        )

        try await templates.save(template)
        #expect(try await templates.template(id: templateID) == template)

        var renamed = template
        renamed.name = "Queue v2"
        try await templates.save(renamed)
        #expect(try await templates.fetchAll(includeBuiltIn: true).count == 1)
        #expect(try await templates.template(id: templateID) == renamed)
    }

    @Test("Built-in templates reject modification but allow identical re-saves")
    func builtInTemplatesRejectModification() async throws {
        let context = CoreDataTestContext()
        let templates = context.repositories.templates
        let template = try VoiceTemplate(
            id: coreDataFixedUUID(5),
            name: "Built-in",
            templateText: "Number {number}",
            localeIdentifier: "en_US",
            isBuiltIn: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        try await templates.save(template)

        try await templates.save(template)

        var modified = template
        modified.templateText = "Changed {number}"
        await #expect(
            throws: RepositoryError.relationshipConflict(message: "Built-in voice templates cannot be modified.")
        ) {
            try await templates.save(modified)
        }
        #expect(try await templates.template(id: template.id) == template)
    }

    @Test("Delete rejects missing, built-in, and referenced templates")
    func deleteProtectionRules() async throws {
        let context = CoreDataTestContext()
        let templates = context.repositories.templates
        let missingID = coreDataFixedUUID(6)

        await #expect(throws: RepositoryError.notFound(entity: "VoiceTemplate", id: missingID)) {
            try await templates.delete(id: missingID)
        }

        let builtInID = coreDataFixedUUID(7)
        try await templates.save(
            try VoiceTemplate(
                id: builtInID,
                name: "Built-in",
                templateText: "Number {number}",
                localeIdentifier: "en_US",
                isBuiltIn: true
            )
        )
        await #expect(
            throws: RepositoryError.relationshipConflict(message: "Built-in voice templates cannot be deleted.")
        ) {
            try await templates.delete(id: builtInID)
        }

        let referencedID = coreDataFixedUUID(8)
        try await templates.save(
            try VoiceTemplate(id: referencedID, name: "Custom", templateText: "Call", localeIdentifier: "en_US")
        )
        let boardID = try await context.makeBoard(workspaceValue: 9, boardValue: 10)
        let actionID = coreDataFixedUUID(11)
        try await context.repositories.actions.save(
            try CallAction(
                id: actionID,
                boardID: boardID,
                title: "A001",
                speechText: "A001",
                voiceTemplateID: referencedID
            )
        )
        await #expect(
            throws: RepositoryError.relationshipConflict(
                message: "Cannot delete a voice template referenced by actions."
            )
        ) {
            try await templates.delete(id: referencedID)
        }

        try await context.repositories.actions.delete(id: actionID)
        try await templates.delete(id: referencedID)
        #expect(try await templates.template(id: referencedID) == nil)
    }
}
