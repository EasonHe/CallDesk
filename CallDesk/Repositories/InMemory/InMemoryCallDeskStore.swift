import Foundation

actor InMemoryCallDeskStore {
    enum Operation: String, CaseIterable, Sendable {
        case fetchWorkspaces
        case workspace
        case saveWorkspace
        case deleteWorkspace
        case fetchAllBoards
        case board
        case saveBoard
        case deleteBoard
        case reorderBoards
        case fetchActions
        case action
        case saveAction
        case deleteAction
        case reorderActions
        case fetchTemplates
        case template
        case saveTemplate
        case deleteTemplate
        case saveRecord
        case record
        case fetchRecords
        case deleteRecords
        case deleteAllRecords
        case enforceHistoryRetention
    }

    private var workspacesByID: [UUID: Workspace]
    private var boardsByID: [UUID: CallBoard]
    private var actionsByID: [UUID: CallAction]
    private var templatesByID: [UUID: VoiceTemplate]
    private var recordsByID: [UUID: CallRecord]
    private var failingOperations: Set<Operation> = []

    init(
        workspaces: [Workspace] = [],
        boards: [CallBoard] = [],
        actions: [CallAction] = [],
        templates: [VoiceTemplate] = [],
        records: [CallRecord] = []
    ) throws {
        let indexedWorkspaces = try Self.index(workspaces, entity: "Workspace", id: \.id)
        let indexedBoards = try Self.index(boards, entity: "CallBoard", id: \.id)
        let indexedActions = try Self.index(actions, entity: "CallAction", id: \.id)
        let indexedTemplates = try Self.index(templates, entity: "VoiceTemplate", id: \.id)
        let indexedRecords = try Self.index(records, entity: "CallRecord", id: \.id)

        try Self.validateLiveRelationships(
            workspaces: indexedWorkspaces,
            boards: indexedBoards,
            actions: indexedActions,
            templates: indexedTemplates
        )

        workspacesByID = indexedWorkspaces
        boardsByID = indexedBoards
        actionsByID = indexedActions
        templatesByID = indexedTemplates
        recordsByID = indexedRecords
    }

    func setFailure(_ isEnabled: Bool, for operation: Operation) {
        if isEnabled {
            failingOperations.insert(operation)
        } else {
            failingOperations.remove(operation)
        }
    }

    func checkFailure(for operation: Operation) throws {
        guard failingOperations.contains(operation) else {
            return
        }

        throw RepositoryError.configuredFailure(operation: operation.rawValue)
    }

    func fetchWorkspaces() throws -> [Workspace] {
        try checkFailure(for: .fetchWorkspaces)
        return sortedWorkspaces(workspacesByID.values)
    }

    func workspace(id: UUID) throws -> Workspace? {
        try checkFailure(for: .workspace)
        return workspacesByID[id]
    }

    func saveWorkspace(_ workspace: Workspace) throws {
        try checkFailure(for: .saveWorkspace)
        workspacesByID[workspace.id] = workspace
    }

    func deleteWorkspace(id: UUID) throws {
        try checkFailure(for: .deleteWorkspace)
        guard workspacesByID[id] != nil else {
            throw RepositoryError.notFound(entity: "Workspace", id: id)
        }
        guard !boardsByID.values.contains(where: { $0.workspaceID == id }) else {
            throw RepositoryError.relationshipConflict(
                message: "Cannot delete a workspace that contains boards."
            )
        }

        workspacesByID.removeValue(forKey: id)
    }

    func fetchAllBoards(workspaceID: UUID, includeArchived: Bool) throws -> [CallBoard] {
        try checkFailure(for: .fetchAllBoards)
        let boards = boardsByID.values.filter {
            $0.workspaceID == workspaceID && (includeArchived || !$0.isArchived)
        }
        return sortedBoards(boards)
    }

    func board(id: UUID) throws -> CallBoard? {
        try checkFailure(for: .board)
        return boardsByID[id]
    }

    func saveBoard(_ board: CallBoard) throws {
        try checkFailure(for: .saveBoard)
        guard workspacesByID[board.workspaceID] != nil else {
            throw RepositoryError.relationshipNotFound(entity: "Workspace", id: board.workspaceID)
        }
        if let existingBoard = boardsByID[board.id], existingBoard.workspaceID != board.workspaceID {
            throw RepositoryError.relationshipConflict(message: "Board workspace cannot be changed.")
        }

        boardsByID[board.id] = board
    }

    func deleteBoard(id: UUID) throws {
        try checkFailure(for: .deleteBoard)
        guard boardsByID[id] != nil else {
            throw RepositoryError.notFound(entity: "CallBoard", id: id)
        }
        guard !actionsByID.values.contains(where: { $0.boardID == id }) else {
            throw RepositoryError.relationshipConflict(
                message: "Cannot delete a board that contains actions."
            )
        }

        boardsByID.removeValue(forKey: id)
    }

    func reorderBoards(workspaceID: UUID, orderedIDs: [UUID]) throws {
        try checkFailure(for: .reorderBoards)
        guard workspacesByID[workspaceID] != nil else {
            throw RepositoryError.relationshipNotFound(entity: "Workspace", id: workspaceID)
        }
        let currentBoards = boardsByID.values.filter {
            $0.workspaceID == workspaceID
        }
        guard hasExactMembership(currentBoards.map(\.id), orderedIDs: orderedIDs) else {
            throw RepositoryError.invalidReorder
        }

        let replacements = orderedIDs.enumerated().map { index, id in
            var board = boardsByID[id]
            board?.sortOrder = index
            return board
        }
        guard replacements.allSatisfy({ $0 != nil }) else {
            throw RepositoryError.invalidReorder
        }
        for board in replacements.compactMap({ $0 }) {
            boardsByID[board.id] = board
        }
    }

    func fetchActions(boardID: UUID, includeDisabled: Bool) throws -> [CallAction] {
        try checkFailure(for: .fetchActions)
        let actions = actionsByID.values.filter {
            $0.boardID == boardID && (includeDisabled || $0.isEnabled)
        }
        return sortedActions(actions)
    }

    func action(id: UUID) throws -> CallAction? {
        try checkFailure(for: .action)
        return actionsByID[id]
    }

    func saveAction(_ action: CallAction) throws {
        try checkFailure(for: .saveAction)
        guard boardsByID[action.boardID] != nil else {
            throw RepositoryError.relationshipNotFound(entity: "CallBoard", id: action.boardID)
        }
        if let templateID = action.voiceTemplateID, templatesByID[templateID] == nil {
            throw RepositoryError.relationshipNotFound(entity: "VoiceTemplate", id: templateID)
        }
        if let existingAction = actionsByID[action.id], existingAction.boardID != action.boardID {
            throw RepositoryError.relationshipConflict(message: "Action board cannot be changed.")
        }

        actionsByID[action.id] = action
    }

    func deleteAction(id: UUID) throws {
        try checkFailure(for: .deleteAction)
        guard actionsByID[id] != nil else {
            throw RepositoryError.notFound(entity: "CallAction", id: id)
        }

        actionsByID.removeValue(forKey: id)
    }

    func reorderActions(boardID: UUID, orderedIDs: [UUID]) throws {
        try checkFailure(for: .reorderActions)
        guard boardsByID[boardID] != nil else {
            throw RepositoryError.relationshipNotFound(entity: "CallBoard", id: boardID)
        }
        let currentActions = actionsByID.values.filter { $0.boardID == boardID }
        guard hasExactMembership(currentActions.map(\.id), orderedIDs: orderedIDs) else {
            throw RepositoryError.invalidReorder
        }

        let replacements = orderedIDs.enumerated().map { index, id in
            var action = actionsByID[id]
            action?.sortOrder = index
            return action
        }
        guard replacements.allSatisfy({ $0 != nil }) else {
            throw RepositoryError.invalidReorder
        }
        for action in replacements.compactMap({ $0 }) {
            actionsByID[action.id] = action
        }
    }

    func fetchTemplates(includeBuiltIn: Bool) throws -> [VoiceTemplate] {
        try checkFailure(for: .fetchTemplates)
        let templates = templatesByID.values.filter { includeBuiltIn || !$0.isBuiltIn }
        return sortedTemplates(templates)
    }

    func template(id: UUID) throws -> VoiceTemplate? {
        try checkFailure(for: .template)
        return templatesByID[id]
    }

    func saveTemplate(_ template: VoiceTemplate) throws {
        try checkFailure(for: .saveTemplate)
        if let existingTemplate = templatesByID[template.id],
           existingTemplate.isBuiltIn,
           existingTemplate != template {
            throw RepositoryError.relationshipConflict(message: "Built-in voice templates cannot be modified.")
        }

        templatesByID[template.id] = template
    }

    func deleteTemplate(id: UUID) throws {
        try checkFailure(for: .deleteTemplate)
        guard let template = templatesByID[id] else {
            throw RepositoryError.notFound(entity: "VoiceTemplate", id: id)
        }
        guard !template.isBuiltIn else {
            throw RepositoryError.relationshipConflict(message: "Built-in voice templates cannot be deleted.")
        }
        guard !actionsByID.values.contains(where: { $0.voiceTemplateID == id }) else {
            throw RepositoryError.relationshipConflict(
                message: "Cannot delete a voice template referenced by actions."
            )
        }

        templatesByID.removeValue(forKey: id)
    }

    func record(id: UUID) throws -> CallRecord? {
        try checkFailure(for: .record)
        return recordsByID[id]
    }

    func saveRecord(_ record: CallRecord) throws {
        try checkFailure(for: .saveRecord)

        let existingRecord = recordsByID[record.id]
        if let actionID = record.actionID,
           actionsByID[actionID] == nil,
           existingRecord?.actionID != actionID {
            throw RepositoryError.relationshipNotFound(entity: "CallAction", id: actionID)
        }
        if let boardID = record.boardID,
           boardsByID[boardID] == nil,
           existingRecord?.boardID != boardID {
            throw RepositoryError.relationshipNotFound(entity: "CallBoard", id: boardID)
        }

        recordsByID[record.id] = record
    }

    func fetchRecords(_ filter: CallHistoryFilter) throws -> [CallRecord] {
        try checkFailure(for: .fetchRecords)

        let records = recordsByID.values.filter { record in
            RepositoryDataRules.matches(record, filter: filter)
        }
        let sortedRecords = sortedRecords(records)

        if let limit = filter.limit {
            return Array(sortedRecords.prefix(limit))
        }
        return sortedRecords
    }

    func deleteRecords(ids: Set<UUID>) throws {
        try checkFailure(for: .deleteRecords)
        for id in ids {
            recordsByID.removeValue(forKey: id)
        }
    }

    func deleteAllRecords() throws {
        try checkFailure(for: .deleteAllRecords)
        recordsByID.removeAll()
    }

    func enforceHistoryRetention(_ policy: HistoryRetentionPolicy, now: Date) throws -> Int {
        try checkFailure(for: .enforceHistoryRetention)

        let recordIDsToDelete = RepositoryDataRules.retentionDeletionIDs(
            records: Array(recordsByID.values),
            policy: policy,
            now: now
        )
        for id in recordIDsToDelete {
            recordsByID.removeValue(forKey: id)
        }
        return recordIDsToDelete.count
    }

    private static func index<Value>(
        _ values: [Value],
        entity: String,
        id: (Value) -> UUID
    ) throws -> [UUID: Value] {
        var indexedValues: [UUID: Value] = [:]

        for value in values {
            let identifier = id(value)
            guard indexedValues[identifier] == nil else {
                throw RepositoryError.duplicateIdentifier(entity: entity, id: identifier)
            }
            indexedValues[identifier] = value
        }

        return indexedValues
    }

    private static func validateLiveRelationships(
        workspaces: [UUID: Workspace],
        boards: [UUID: CallBoard],
        actions: [UUID: CallAction],
        templates: [UUID: VoiceTemplate]
    ) throws {
        for board in boards.values {
            guard workspaces[board.workspaceID] != nil else {
                throw RepositoryError.relationshipNotFound(
                    entity: "Workspace",
                    id: board.workspaceID
                )
            }
        }

        for action in actions.values {
            guard boards[action.boardID] != nil else {
                throw RepositoryError.relationshipNotFound(entity: "CallBoard", id: action.boardID)
            }

            if let templateID = action.voiceTemplateID {
                guard templates[templateID] != nil else {
                    throw RepositoryError.relationshipNotFound(
                        entity: "VoiceTemplate",
                        id: templateID
                    )
                }
            }
        }
    }

    private func hasExactMembership(_ currentIDs: [UUID], orderedIDs: [UUID]) -> Bool {
        RepositoryDataRules.hasExactMembership(currentIDs, orderedIDs: orderedIDs)
    }

    private func sortedWorkspaces(_ workspaces: Dictionary<UUID, Workspace>.Values) -> [Workspace] {
        RepositoryDataRules.sortedWorkspaces(workspaces)
    }

    private func sortedBoards(_ boards: some Sequence<CallBoard>) -> [CallBoard] {
        RepositoryDataRules.sortedBoards(boards)
    }

    private func sortedActions(_ actions: some Sequence<CallAction>) -> [CallAction] {
        RepositoryDataRules.sortedActions(actions)
    }

    private func sortedTemplates(_ templates: some Sequence<VoiceTemplate>) -> [VoiceTemplate] {
        RepositoryDataRules.sortedTemplates(templates)
    }

    private func sortedRecords(_ records: some Sequence<CallRecord>) -> [CallRecord] {
        RepositoryDataRules.sortedRecords(records)
    }
}
