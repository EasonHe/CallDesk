import Foundation

nonisolated protocol VoiceTemplateRepository: Sendable {
    func fetchAll(includeBuiltIn: Bool) async throws -> [VoiceTemplate]
    func template(id: UUID) async throws -> VoiceTemplate?
    func save(_ template: VoiceTemplate) async throws
    func delete(id: UUID) async throws
}
