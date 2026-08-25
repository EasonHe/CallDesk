import Foundation

nonisolated enum CallActionType: String, CaseIterable, Codable, Sendable {
    case queueNumber
    case announcement
    case operationalMessage
    case promptOnly
}

nonisolated enum CallActionStyle: String, CaseIterable, Codable, Sendable {
    case standard
    case accent
    case success
    case warning
    case critical
    case neutral
}

/// How a call action produces its announcement: synthesized speech from
/// `speechText`, or playback of an imported audio clip.
nonisolated enum CallActionPlaybackMode: String, CaseIterable, Codable, Sendable {
    case text
    case audio
}

nonisolated struct CallAction: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    let boardID: UUID
    var title: String
    var speechText: String
    var type: CallActionType
    var voiceTemplateID: UUID?
    var sortOrder: Int
    var style: CallActionStyle
    var playbackMode: CallActionPlaybackMode
    var audioFileName: String?
    var promptToneEnabled: Bool
    var storesInRecentCalls: Bool
    var isEnabled: Bool
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        boardID: UUID,
        title: String,
        speechText: String,
        type: CallActionType = .announcement,
        voiceTemplateID: UUID? = nil,
        sortOrder: Int = 0,
        style: CallActionStyle = .standard,
        playbackMode: CallActionPlaybackMode = .text,
        audioFileName: String? = nil,
        promptToneEnabled: Bool = true,
        storesInRecentCalls: Bool = true,
        isEnabled: Bool = true,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        now: Date = Date()
    ) throws {
        let resolvedCreatedAt = createdAt ?? now
        let resolvedUpdatedAt = updatedAt ?? resolvedCreatedAt

        guard sortOrder >= 0 else {
            throw DomainValidationError.invalidSortOrder
        }
        guard resolvedUpdatedAt >= resolvedCreatedAt else {
            throw DomainValidationError.invalidDateRange
        }

        let normalizedSpeechText = Self.trimmedText(speechText)
        let normalizedAudioFileName = Self.normalizedOptionalText(audioFileName)
        switch playbackMode {
        case .audio:
            // Audio actions announce by playing an imported clip, so a clip
            // reference is required; the spoken text becomes optional.
            guard normalizedAudioFileName != nil else {
                throw DomainValidationError.emptyText(field: "audioFileName")
            }
        case .text:
            guard type == .promptOnly || !normalizedSpeechText.isEmpty else {
                throw DomainValidationError.emptyText(field: "speechText")
            }
        }

        self.id = id
        self.boardID = boardID
        self.title = try Self.validatedTitle(title)
        self.speechText = normalizedSpeechText
        self.type = type
        self.voiceTemplateID = voiceTemplateID
        self.sortOrder = sortOrder
        self.style = style
        self.playbackMode = playbackMode
        self.audioFileName = normalizedAudioFileName
        self.promptToneEnabled = promptToneEnabled
        self.storesInRecentCalls = storesInRecentCalls
        self.isEnabled = isEnabled
        self.createdAt = resolvedCreatedAt
        self.updatedAt = resolvedUpdatedAt
    }

    private static func validatedTitle(_ title: String) throws -> String {
        let trimmedTitle = trimmedText(title)
        guard !trimmedTitle.isEmpty else {
            throw DomainValidationError.emptyName(field: "title")
        }
        return trimmedTitle
    }

    private static func normalizedOptionalText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }
        let trimmed = trimmedText(text)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func trimmedText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
