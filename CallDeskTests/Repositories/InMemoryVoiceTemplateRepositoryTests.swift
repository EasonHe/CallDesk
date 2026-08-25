import Foundation
import Testing
@testable import CallDesk

@Suite("In-memory voice template repository")
struct InMemoryVoiceTemplateRepositoryTests {
    @Test("Fetch excludes built-in templates when requested and sorts by name then identifier")
    func fetchFiltersBuiltInsAndSorts() async throws {
        let firstID = fixedUUID(1)
        let secondID = fixedUUID(2)
        let builtInID = fixedUUID(3)
        let store = try InMemoryCallDeskStore(
            templates: [
                try VoiceTemplate(id: secondID, name: "Alpha", templateText: "Hello", localeIdentifier: "en-US"),
                try VoiceTemplate(id: firstID, name: "Alpha", templateText: "Hi", localeIdentifier: "en-US"),
                try VoiceTemplate(id: builtInID, name: "Built in", templateText: "Built", localeIdentifier: "en-US", isBuiltIn: true)
            ]
        )
        let repository = InMemoryVoiceTemplateRepository(store: store)

        #expect(try await repository.fetchAll(includeBuiltIn: false).map(\.id) == [firstID, secondID])
        #expect(try await repository.fetchAll(includeBuiltIn: true).map(\.id) == [firstID, secondID, builtInID])
    }

    @Test("Built-in templates cannot be modified or deleted")
    func builtInTemplatesAreProtected() async throws {
        let templateID = fixedUUID(4)
        let builtIn = try VoiceTemplate(id: templateID, name: "Built in", templateText: "Hello", localeIdentifier: "en-US", isBuiltIn: true)
        let store = try InMemoryCallDeskStore(templates: [builtIn])
        let repository = InMemoryVoiceTemplateRepository(store: store)

        await #expect(
            throws: RepositoryError.relationshipConflict(
                message: "Built-in voice templates cannot be modified."
            )
        ) {
            try await repository.save(
                try VoiceTemplate(id: templateID, name: "Changed", templateText: "Changed", localeIdentifier: "en-US", isBuiltIn: true)
            )
        }
        await #expect(
            throws: RepositoryError.relationshipConflict(
                message: "Built-in voice templates cannot be deleted."
            )
        ) {
            try await repository.delete(id: templateID)
        }
        #expect(try await repository.template(id: templateID) == builtIn)
    }

    @Test("Referenced templates cannot be deleted")
    func referencedTemplatesAreProtected() async throws {
        let workspaceID = fixedUUID(5)
        let boardID = fixedUUID(6)
        let templateID = fixedUUID(7)
        let template = try VoiceTemplate(id: templateID, name: "Custom", templateText: "Hello", localeIdentifier: "en-US")
        let store = try InMemoryCallDeskStore(
            workspaces: [try Workspace(id: workspaceID, name: "Operations")],
            boards: [try CallBoard(id: boardID, workspaceID: workspaceID, name: "Queue", sortOrder: 0)],
            actions: [try CallAction(id: fixedUUID(8), boardID: boardID, title: "A001", speechText: "A001", voiceTemplateID: templateID)],
            templates: [template]
        )
        let repository = InMemoryVoiceTemplateRepository(store: store)

        await #expect(
            throws: RepositoryError.relationshipConflict(
                message: "Cannot delete a voice template referenced by actions."
            )
        ) {
            try await repository.delete(id: templateID)
        }
        #expect(try await repository.template(id: templateID) == template)
    }

    @Test("Save lookup and delete complete custom template CRUD")
    func saveLookupAndDeleteTemplate() async throws {
        let templateID = fixedUUID(9)
        let template = try VoiceTemplate(id: templateID, name: "Custom", templateText: "Hello", localeIdentifier: "en-US")
        let repository = InMemoryVoiceTemplateRepository(store: try InMemoryCallDeskStore())

        try await repository.save(template)
        #expect(try await repository.template(id: templateID) == template)
        try await repository.delete(id: templateID)
        #expect(try await repository.template(id: templateID) == nil)
    }

    @Test("Configured template read and write failures leave templates unchanged")
    func configuredFailuresLeaveTemplatesUnchanged() async throws {
        let template = try VoiceTemplate(id: fixedUUID(10), name: "Custom", templateText: "Hello", localeIdentifier: "en-US")
        let store = try InMemoryCallDeskStore(templates: [template])
        let repository = InMemoryVoiceTemplateRepository(store: store)

        await store.setFailure(true, for: .fetchTemplates)
        await #expect(throws: RepositoryError.configuredFailure(operation: "fetchTemplates")) {
            try await repository.fetchAll(includeBuiltIn: true)
        }
        await store.setFailure(false, for: .fetchTemplates)

        await store.setFailure(true, for: .saveTemplate)
        await #expect(throws: RepositoryError.configuredFailure(operation: "saveTemplate")) {
            try await repository.save(try VoiceTemplate(id: fixedUUID(11), name: "New", templateText: "New", localeIdentifier: "en-US"))
        }
        await store.setFailure(false, for: .saveTemplate)

        #expect(try await repository.fetchAll(includeBuiltIn: true) == [template])
    }

    private func fixedUUID(_ value: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
    }
}
