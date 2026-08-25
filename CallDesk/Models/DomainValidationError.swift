import Foundation

nonisolated enum DomainValidationError: Error, Equatable, Sendable {
    case emptyName(field: String)
    case emptyText(field: String)
    case invalidSortOrder
    case invalidColumnCount
    case invalidRange(field: String)
    case invalidDateRange
    case malformedTemplate
    case missingTemplateValue(String)
    case invalidRepeatIndex
    case invalidStateTransition
}
