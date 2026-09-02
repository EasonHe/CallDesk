import Foundation

struct InMemoryVoiceTemplateRepository: VoiceTemplateRepository {
    private let store: InMemoryCallDeskStore

    init(store: InMemoryCallDeskStore) {
        self.store = store
    }

    func fetchAll(includeBuiltIn: Bool) async throws -> [VoiceTemplate] {
        try await store.fetchTemplates(includeBuiltIn: includeBuiltIn)
    }

    func template(id: UUID) async throws -> VoiceTemplate? {
        try await store.template(id: id)
    }

    func save(_ template: VoiceTemplate) async throws {
        try await store.saveTemplate(template)
    }

    func delete(id: UUID) async throws {
        try await store.deleteTemplate(id: id)
    }
}
