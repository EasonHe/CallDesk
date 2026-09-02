import Foundation

nonisolated enum CallDeskSampleData {
    nonisolated struct Catalog: Equatable, Sendable {
        let workspace: Workspace
        let boards: [CallBoard]
        let actions: [CallAction]
        let templates: [VoiceTemplate]
        let records: [CallRecord]

        var workspaces: [Workspace] { [workspace] }
    }

    static let catalog = makeCatalog()
    static let workspace = catalog.workspace
    static let boards = catalog.boards
    static let actions = catalog.actions
    static let templates = catalog.templates
    static let records = catalog.records
    static let diningQueueTemplate = catalog.templates[0]
    static let idleLiveCall = LiveCallState.idle
    static let speakingLiveCall = checked {
        try LiveCallState(actionID: actionIDs[0], boardID: boardIDs[0], title: "A021", spokenText: "请 A021 前来取餐", phase: .speaking, startedAt: referenceDate)
    }
    static let displayState = DisplayPresentationState.idle(updatedAt: referenceDate)
    static let previewSettings = CallDeskSettings.default

    static func makeCatalog() -> Catalog {
        let workspace = checked { try Workspace(id: workspaceID, name: "CallDesk Demo", createdAt: referenceDate) }
        let boards = [
            checked { try CallBoard(id: boardIDs[0], workspaceID: workspaceID, name: "叫号面板", subtitle: "综合服务大厅", sortOrder: 0, createdAt: referenceDate) },
            checked { try CallBoard(id: boardIDs[1], workspaceID: workspaceID, name: "广播通知", subtitle: "公共播放", sortOrder: 1, createdAt: referenceDate) }
        ]
        let templates = [
            checked { try VoiceTemplate(id: templateIDs[0], name: "餐饮取餐", templateText: "请，{number} 号，前来取餐。", localeIdentifier: "zh-Hans", isBuiltIn: true, createdAt: referenceDate) }
        ]
        let actions = [
            action("A021", "请 A021 号，到 1 号窗口", 0),
            action("A022", "请 A022 号，到 2 号窗口", 1),
            action("A023", "请 A023 号，到 3 号窗口", 2),
            action("VIP", "请 VIP01 号，到 VIP 窗口", 3),
            announcement("开始签到", "开始签到。", 0),
            announcement("暂停办理", "暂停办理。", 1),
            announcement("请保持安静", "请保持安静。", 2),
            announcement("会议将在五分钟后开始", "会议将在五分钟后开始。", 3)
        ]

        let records = [
            checked { try CallRecord(id: recordIDs[0], actionID: actions[0].id, boardID: boardIDs[0], actionTitleSnapshot: "A021", spokenTextSnapshot: actions[0].speechText, startedAt: referenceDate, completedAt: referenceDate.addingTimeInterval(5), result: .completed) },
            checked { try CallRecord(id: recordIDs[1], actionID: actions[0].id, boardID: boardIDs[0], actionTitleSnapshot: "A021", spokenTextSnapshot: actions[0].speechText, startedAt: referenceDate.addingTimeInterval(60), completedAt: referenceDate.addingTimeInterval(65), result: .completed, repeatIndex: 1) },
            checked { try CallRecord(id: recordIDs[2], actionID: actions[4].id, boardID: boardIDs[1], actionTitleSnapshot: "开始签到", spokenTextSnapshot: actions[4].speechText, startedAt: referenceDate.addingTimeInterval(120), completedAt: referenceDate.addingTimeInterval(121), result: .cancelled) },
            checked { try CallRecord(id: recordIDs[3], actionID: actions[5].id, boardID: boardIDs[1], actionTitleSnapshot: "暂停办理", spokenTextSnapshot: actions[5].speechText, startedAt: referenceDate.addingTimeInterval(180), completedAt: referenceDate.addingTimeInterval(181), result: .failed, errorDescription: "Output unavailable") }
        ]
        return Catalog(workspace: workspace, boards: boards, actions: actions, templates: templates, records: records)
    }

    static func makeActions() -> [CallAction] { catalog.actions }

    private static func action(_ title: String, _ speech: String, _ order: Int) -> CallAction {
        checked { try CallAction(id: actionIDs[order], boardID: boardIDs[0], title: title, speechText: speech, type: .queueNumber, voiceTemplateID: templateIDs[0], sortOrder: order, createdAt: referenceDate) }
    }

    private static func announcement(_ title: String, _ speech: String, _ order: Int) -> CallAction {
        checked { try CallAction(id: actionIDs[order + 4], boardID: boardIDs[1], title: title, speechText: speech, type: .operationalMessage, sortOrder: order, createdAt: referenceDate) }
    }

    private static func checked<T>(_ build: () throws -> T) -> T {
        do { return try build() } catch { preconditionFailure("Invalid CallDesk sample data: \(error)") }
    }

    private static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
    private static let workspaceID = fixedUUID(1)
    private static let boardIDs = (4...5).map(fixedUUID)
    private static let actionIDs = (6...13).map(fixedUUID)
    private static let templateIDs = (14...14).map(fixedUUID)
    private static let recordIDs = (19...22).map(fixedUUID)

    private static func fixedUUID(_ value: Int) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, UInt8(value)))
    }
}
