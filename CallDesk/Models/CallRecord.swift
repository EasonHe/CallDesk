import Foundation

nonisolated enum CallResult: String, CaseIterable, Codable, Sendable {
    case queued
    case completed
    case cancelled
    case interrupted
    case failed
}

nonisolated struct CallRecord: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    let actionID: UUID?
    let boardID: UUID?
    let actionTitleSnapshot: String
    let spokenTextSnapshot: String
    let audioFileNameSnapshot: String?
    let startedAt: Date
    let completedAt: Date?
    let result: CallResult
    let repeatIndex: Int
    let audioRouteName: String?
    let errorDescription: String?

    init(
        id: UUID = UUID(),
        actionID: UUID? = nil,
        boardID: UUID? = nil,
        actionTitleSnapshot: String,
        spokenTextSnapshot: String,
        audioFileNameSnapshot: String? = nil,
        startedAt: Date,
        completedAt: Date? = nil,
        result: CallResult = .queued,
        repeatIndex: Int = 0,
        audioRouteName: String? = nil,
        errorDescription: String? = nil
    ) throws {
        guard repeatIndex >= 0 else {
            throw DomainValidationError.invalidRepeatIndex
        }

        if let completedAt {
            guard completedAt >= startedAt else {
                throw DomainValidationError.invalidDateRange
            }
        }

        switch result {
        case .queued:
            guard completedAt == nil else {
                throw DomainValidationError.invalidDateRange
            }
        case .completed, .cancelled, .interrupted, .failed:
            guard completedAt != nil else {
                throw DomainValidationError.invalidDateRange
            }
        }

        let normalizedTitle = Self.trimmedText(actionTitleSnapshot)
        guard !normalizedTitle.isEmpty else {
            throw DomainValidationError.emptyName(field: "actionTitleSnapshot")
        }

        let normalizedSpokenText = Self.trimmedText(spokenTextSnapshot)
        guard !normalizedSpokenText.isEmpty else {
            throw DomainValidationError.emptyText(field: "spokenTextSnapshot")
        }

        let normalizedErrorDescription = Self.normalizedOptionalText(errorDescription)
        if result == .failed, normalizedErrorDescription == nil {
            throw DomainValidationError.emptyText(field: "errorDescription")
        }

        self.id = id
        self.actionID = actionID
        self.boardID = boardID
        self.actionTitleSnapshot = normalizedTitle
        self.spokenTextSnapshot = normalizedSpokenText
        self.audioFileNameSnapshot = Self.normalizedOptionalText(audioFileNameSnapshot)
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.result = result
        self.repeatIndex = repeatIndex
        self.audioRouteName = Self.normalizedOptionalText(audioRouteName)
        self.errorDescription = normalizedErrorDescription
    }

    func completing(at date: Date) throws -> CallRecord {
        try terminalRecord(result: .completed, completedAt: date)
    }

    func failing(at date: Date, message: String) throws -> CallRecord {
        try terminalRecord(result: .failed, completedAt: date, errorDescription: message)
    }

    func cancelling(at date: Date) throws -> CallRecord {
        try terminalRecord(result: .cancelled, completedAt: date)
    }

    func interrupting(at date: Date) throws -> CallRecord {
        try terminalRecord(result: .interrupted, completedAt: date)
    }

    private func terminalRecord(
        result: CallResult,
        completedAt: Date,
        errorDescription: String? = nil
    ) throws -> CallRecord {
        guard self.result == .queued else {
            throw DomainValidationError.invalidStateTransition
        }

        return try CallRecord(
            id: id,
            actionID: actionID,
            boardID: boardID,
            actionTitleSnapshot: actionTitleSnapshot,
            spokenTextSnapshot: spokenTextSnapshot,
            audioFileNameSnapshot: audioFileNameSnapshot,
            startedAt: startedAt,
            completedAt: completedAt,
            result: result,
            repeatIndex: repeatIndex,
            audioRouteName: audioRouteName,
            errorDescription: errorDescription
        )
    }

    private static func normalizedOptionalText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }

        let trimmedText = trimmedText(text)
        return trimmedText.isEmpty ? nil : trimmedText
    }

    private static func trimmedText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
