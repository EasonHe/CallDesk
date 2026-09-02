import CoreData
import Foundation

/// Managed object subclasses backing the CallDesk Core Data model.
///
/// These types never leave the persistence layer; repositories always
/// translate them into plain domain values before returning results.
@objc(CDWorkspace)
nonisolated final class CDWorkspace: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var note: String?
    @NSManaged var isArchived: Bool
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date

    func apply(_ workspace: Workspace) {
        id = workspace.id
        name = workspace.name
        note = workspace.note
        isArchived = workspace.isArchived
        createdAt = workspace.createdAt
        updatedAt = workspace.updatedAt
    }

    func domainValue() throws -> Workspace {
        try Workspace(
            id: id,
            name: name,
            note: note,
            isArchived: isArchived,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

@objc(CDCallBoard)
nonisolated final class CDCallBoard: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var workspaceID: UUID
    @NSManaged var name: String
    @NSManaged var subtitle: String?
    @NSManaged var sortOrder: Int64
    @NSManaged var preferredColumnCount: NSNumber?
    @NSManaged var showsRecentCalls: Bool
    @NSManaged var isArchived: Bool
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date

    func apply(_ board: CallBoard) {
        id = board.id
        workspaceID = board.workspaceID
        name = board.name
        subtitle = board.subtitle
        sortOrder = Int64(board.sortOrder)
        preferredColumnCount = board.preferredColumnCount.map(NSNumber.init(value:))
        showsRecentCalls = board.showsRecentCalls
        isArchived = board.isArchived
        createdAt = board.createdAt
        updatedAt = board.updatedAt
    }

    func domainValue() throws -> CallBoard {
        try CallBoard(
            id: id,
            workspaceID: workspaceID,
            name: name,
            subtitle: subtitle,
            sortOrder: Int(sortOrder),
            preferredColumnCount: preferredColumnCount?.intValue,
            showsRecentCalls: showsRecentCalls,
            isArchived: isArchived,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

@objc(CDCallAction)
nonisolated final class CDCallAction: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var boardID: UUID
    @NSManaged var title: String
    @NSManaged var speechText: String
    @NSManaged var typeRawValue: String
    @NSManaged var voiceTemplateID: UUID?
    @NSManaged var sortOrder: Int64
    @NSManaged var styleRawValue: String
    @NSManaged var playbackModeRawValue: String
    @NSManaged var audioFileName: String?
    @NSManaged var promptToneEnabled: Bool
    @NSManaged var storesInRecentCalls: Bool
    @NSManaged var isEnabled: Bool
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date

    func apply(_ action: CallAction) {
        id = action.id
        boardID = action.boardID
        title = action.title
        speechText = action.speechText
        typeRawValue = action.type.rawValue
        voiceTemplateID = action.voiceTemplateID
        sortOrder = Int64(action.sortOrder)
        styleRawValue = action.style.rawValue
        playbackModeRawValue = action.playbackMode.rawValue
        audioFileName = action.audioFileName
        promptToneEnabled = action.promptToneEnabled
        storesInRecentCalls = action.storesInRecentCalls
        isEnabled = action.isEnabled
        createdAt = action.createdAt
        updatedAt = action.updatedAt
    }

    func domainValue() throws -> CallAction {
        guard let type = CallActionType(rawValue: typeRawValue),
              let style = CallActionStyle(rawValue: styleRawValue),
              let playbackMode = CallActionPlaybackMode(rawValue: playbackModeRawValue) else {
            throw RepositoryError.storageFailure(
                message: "Stored CallAction \(id) has an unknown type, style, or playback mode."
            )
        }
        return try CallAction(
            id: id,
            boardID: boardID,
            title: title,
            speechText: speechText,
            type: type,
            voiceTemplateID: voiceTemplateID,
            sortOrder: Int(sortOrder),
            style: style,
            playbackMode: playbackMode,
            audioFileName: audioFileName,
            promptToneEnabled: promptToneEnabled,
            storesInRecentCalls: storesInRecentCalls,
            isEnabled: isEnabled,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

@objc(CDVoiceTemplate)
nonisolated final class CDVoiceTemplate: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var templateText: String
    @NSManaged var localeIdentifier: String
    @NSManaged var isBuiltIn: Bool
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date

    func apply(_ template: VoiceTemplate) {
        id = template.id
        name = template.name
        templateText = template.templateText
        localeIdentifier = template.localeIdentifier
        isBuiltIn = template.isBuiltIn
        createdAt = template.createdAt
        updatedAt = template.updatedAt
    }

    func domainValue() throws -> VoiceTemplate {
        try VoiceTemplate(
            id: id,
            name: name,
            templateText: templateText,
            localeIdentifier: localeIdentifier,
            isBuiltIn: isBuiltIn,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

@objc(CDCallRecord)
nonisolated final class CDCallRecord: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var actionID: UUID?
    @NSManaged var boardID: UUID?
    @NSManaged var actionTitleSnapshot: String
    @NSManaged var spokenTextSnapshot: String
    @NSManaged var audioFileNameSnapshot: String?
    @NSManaged var startedAt: Date
    @NSManaged var completedAt: Date?
    @NSManaged var resultRawValue: String
    @NSManaged var repeatIndex: Int64
    @NSManaged var audioRouteName: String?
    @NSManaged var errorDescription: String?

    func apply(_ record: CallRecord) {
        id = record.id
        actionID = record.actionID
        boardID = record.boardID
        actionTitleSnapshot = record.actionTitleSnapshot
        spokenTextSnapshot = record.spokenTextSnapshot
        audioFileNameSnapshot = record.audioFileNameSnapshot
        startedAt = record.startedAt
        completedAt = record.completedAt
        resultRawValue = record.result.rawValue
        repeatIndex = Int64(record.repeatIndex)
        audioRouteName = record.audioRouteName
        errorDescription = record.errorDescription
    }

    func domainValue() throws -> CallRecord {
        guard let result = CallResult(rawValue: resultRawValue) else {
            throw RepositoryError.storageFailure(
                message: "Stored CallRecord \(id) has an unknown result."
            )
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
            repeatIndex: Int(repeatIndex),
            audioRouteName: audioRouteName,
            errorDescription: errorDescription
        )
    }
}
