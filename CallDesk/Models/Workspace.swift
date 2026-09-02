import Foundation

nonisolated struct Workspace: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    private(set) var name: String
    var note: String?
    var isArchived: Bool
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        note: String? = nil,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) throws {
        let resolvedUpdatedAt = updatedAt ?? createdAt
        guard resolvedUpdatedAt >= createdAt else {
            throw DomainValidationError.invalidDateRange
        }

        self.id = id
        self.name = try Self.validatedName(name)
        self.note = Self.normalizedOptionalText(note)
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = resolvedUpdatedAt
    }

    mutating func rename(to name: String, at date: Date = Date()) throws {
        self.name = try Self.validatedName(name)
        updatedAt = date
    }

    private static func validatedName(_ name: String) throws -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw DomainValidationError.emptyName(field: "name")
        }
        return trimmedName
    }

    private static func normalizedOptionalText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? nil : trimmedText
    }
}
