import Foundation

nonisolated struct CoreDataVoiceTemplateRepository: VoiceTemplateRepository {
    private let store: CoreDataCallDeskStore

    init(store: CoreDataCallDeskStore) {
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
