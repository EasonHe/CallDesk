import Foundation

nonisolated struct VoiceTemplate: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var templateText: String
    var localeIdentifier: String
    var isBuiltIn: Bool
    let createdAt: Date
    var updatedAt: Date

    var placeholders: Set<String> {
        (try? Self.placeholderNames(in: templateText)) ?? []
    }

    init(
        id: UUID = UUID(),
        name: String,
        templateText: String,
        localeIdentifier: String,
        isBuiltIn: Bool = false,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        now: Date = Date()
    ) throws {
        let resolvedCreatedAt = createdAt ?? now
        let resolvedUpdatedAt = updatedAt ?? resolvedCreatedAt

        guard resolvedUpdatedAt >= resolvedCreatedAt else {
            throw DomainValidationError.invalidDateRange
        }

        let normalizedName = Self.trimmedText(name)
        guard !normalizedName.isEmpty else {
            throw DomainValidationError.emptyName(field: "name")
        }

        let trimmedTemplateText = Self.trimmedText(templateText)
        guard !trimmedTemplateText.isEmpty else {
            throw DomainValidationError.emptyText(field: "templateText")
        }

        let normalizedLocaleIdentifier = Self.trimmedText(localeIdentifier)
        guard !normalizedLocaleIdentifier.isEmpty else {
            throw DomainValidationError.emptyText(field: "localeIdentifier")
        }

        self.id = id
        self.name = normalizedName
        self.templateText = templateText
        self.localeIdentifier = normalizedLocaleIdentifier
        self.isBuiltIn = isBuiltIn
        self.createdAt = resolvedCreatedAt
        self.updatedAt = resolvedUpdatedAt
        _ = try Self.placeholderNames(in: templateText)
    }

    func render(values: [String: String]) throws -> String {
        _ = try Self.placeholderNames(in: templateText)

        var renderedText = ""
        var index = templateText.startIndex

        while index < templateText.endIndex {
            let character = templateText[index]
            if character == "{" {
                let nameStart = templateText.index(after: index)
                guard let closingBrace = templateText[nameStart...].firstIndex(of: "}") else {
                    throw DomainValidationError.malformedTemplate
                }

                let name = String(templateText[nameStart..<closingBrace])
                guard let value = values[name] else {
                    throw DomainValidationError.missingTemplateValue(name)
                }

                renderedText += Self.trimmedText(value)
                index = templateText.index(after: closingBrace)
            } else {
                renderedText.append(character)
                index = templateText.index(after: index)
            }
        }

        return renderedText
    }

    private static func placeholderNames(in templateText: String) throws -> Set<String> {
        var names = Set<String>()
        var index = templateText.startIndex

        while index < templateText.endIndex {
            let character = templateText[index]
            switch character {
            case "{":
                let nameStart = templateText.index(after: index)
                guard let closingBrace = templateText[nameStart...].firstIndex(of: "}") else {
                    throw DomainValidationError.malformedTemplate
                }

                let name = String(templateText[nameStart..<closingBrace])
                guard isValidPlaceholderName(name) else {
                    throw DomainValidationError.malformedTemplate
                }

                names.insert(name)
                index = templateText.index(after: closingBrace)
            case "}":
                throw DomainValidationError.malformedTemplate
            default:
                index = templateText.index(after: index)
            }
        }

        return names
    }

    private static func isValidPlaceholderName(_ name: String) -> Bool {
        guard !name.isEmpty else {
            return false
        }

        return name.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 65...90, 95, 97...122:
                true
            default:
                false
            }
        }
    }

    private static func trimmedText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
