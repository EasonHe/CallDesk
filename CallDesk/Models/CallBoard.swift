import Foundation

nonisolated struct CallBoard: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    let workspaceID: UUID
    private(set) var name: String
    var subtitle: String?
    var sortOrder: Int
    var preferredColumnCount: Int?
    var showsRecentCalls: Bool
    var isArchived: Bool
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        workspaceID: UUID,
        name: String,
        subtitle: String? = nil,
        sortOrder: Int,
        preferredColumnCount: Int? = nil,
        showsRecentCalls: Bool = true,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) throws {
        let resolvedUpdatedAt = updatedAt ?? createdAt
        guard sortOrder >= 0 else {
            throw DomainValidationError.invalidSortOrder
        }
        if let preferredColumnCount, !(2...8).contains(preferredColumnCount) {
            throw DomainValidationError.invalidColumnCount
        }
        guard resolvedUpdatedAt >= createdAt else {
            throw DomainValidationError.invalidDateRange
        }

        self.id = id
        self.workspaceID = workspaceID
        self.name = try Self.validatedName(name)
        self.subtitle = Self.normalizedOptionalText(subtitle)
        self.sortOrder = sortOrder
        self.preferredColumnCount = preferredColumnCount
        self.showsRecentCalls = showsRecentCalls
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = resolvedUpdatedAt
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
