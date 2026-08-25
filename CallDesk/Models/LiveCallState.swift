import Foundation

nonisolated enum LiveCallPhase: Equatable, Sendable {
    case idle
    case queued
    case preparing
    case playingPrompt
    case speaking
    case completed
    case cancelled
    case interrupted
    case failed(message: String)
}

nonisolated struct LiveCallState: Equatable, Sendable {
    let actionID: UUID?
    let boardID: UUID?
    let title: String?
    let spokenText: String?
    let phase: LiveCallPhase
    let repeatIndex: Int
    let startedAt: Date?

    static let idle = LiveCallState(uncheckedActionID: nil,
        boardID: nil,
        title: nil,
        spokenText: nil,
        phase: .idle,
        repeatIndex: 0,
        startedAt: nil
    )

    init(
        actionID: UUID? = nil,
        boardID: UUID? = nil,
        title: String? = nil,
        spokenText: String? = nil,
        phase: LiveCallPhase = .idle,
        repeatIndex: Int = 0,
        startedAt: Date? = nil
    ) throws {
        guard repeatIndex >= 0 else {
            throw DomainValidationError.invalidRepeatIndex
        }

        let normalizedTitle = Self.normalizedOptionalText(title)
        let normalizedSpokenText = Self.normalizedOptionalText(spokenText)

        if phase == .idle {
            guard actionID == nil,
                  boardID == nil,
                  normalizedTitle == nil,
                  normalizedSpokenText == nil,
                  repeatIndex == 0,
                  startedAt == nil else {
                throw DomainValidationError.invalidStateTransition
            }
        }

        self.actionID = actionID
        self.boardID = boardID
        self.title = normalizedTitle
        self.spokenText = normalizedSpokenText
        self.phase = phase
        self.repeatIndex = repeatIndex
        self.startedAt = startedAt
    }

    private init(
        uncheckedActionID actionID: UUID?,
        boardID: UUID?,
        title: String?,
        spokenText: String?,
        phase: LiveCallPhase,
        repeatIndex: Int,
        startedAt: Date?
    ) {
        self.actionID = actionID
        self.boardID = boardID
        self.title = title
        self.spokenText = spokenText
        self.phase = phase
        self.repeatIndex = repeatIndex
        self.startedAt = startedAt
    }

    private static func normalizedOptionalText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? nil : trimmedText
    }
}
