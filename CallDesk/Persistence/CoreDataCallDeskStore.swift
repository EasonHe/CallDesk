import CoreData
import Foundation

/// Serializes all Core Data work for the CallDesk repositories on a single
/// background context and mirrors the relationship, reorder, and retention
/// semantics of `InMemoryCallDeskStore`.
///
/// Only Sendable domain values cross the context boundary; managed objects
/// never leave the perform blocks.
nonisolated final class CoreDataCallDeskStore: @unchecked Sendable {
    private let context: NSManagedObjectContext
    private let waitForPersistentStore: @Sendable () async -> Void
    private let diagnostics: StartupDiagnostics

    init(persistence: PersistenceController) {
        context = persistence.newBackgroundContext()
        waitForPersistentStore = { await persistence.waitUntilReady() }
        diagnostics = persistence.diagnostics
    }

    init(
        context: NSManagedObjectContext,
        waitForPersistentStore: @escaping @Sendable () async -> Void
    ) {
        self.context = context
        self.waitForPersistentStore = waitForPersistentStore
        diagnostics = StartupDiagnostics()
    }

    // MARK: - Workspaces

    func fetchWorkspaces() async throws -> [Workspace] {
        try await performRead {
            RepositoryDataRules.sortedWorkspaces(try self.allDomainWorkspaces())
        }
    }

    func workspace(id: UUID) async throws -> Workspace? {
        try await performRead {
            try self.entity(CDWorkspace.self, id: id)?.domainValue()
        }
    }

    func saveWorkspace(_ workspace: Workspace) async throws {
        try await performWrite {
            let entity = try self.entity(CDWorkspace.self, id: workspace.id) ?? CDWorkspace(context: self.context)
            entity.apply(workspace)
        }
    }

    func deleteWorkspace(id: UUID) async throws {
        try await performWrite {
            guard let entity = try self.entity(CDWorkspace.self, id: id) else {
                throw RepositoryError.notFound(entity: "Workspace", id: id)
            }
            let hasBoards = try self.count(CDCallBoard.self, format: "workspaceID == %@", id) > 0
            guard !hasBoards else {
                throw RepositoryError.relationshipConflict(
                    message: "Cannot delete a workspace that contains boards."
                )
            }

            self.context.delete(entity)
        }
    }

    // MARK: - Boards

    func fetchAllBoards(workspaceID: UUID, includeArchived: Bool) async throws -> [CallBoard] {
        try await performRead {
            let boards = try self.domainBoards(workspaceID: workspaceID).filter {
                includeArchived || !$0.isArchived
            }
            return RepositoryDataRules.sortedBoards(boards)
        }
    }

    func board(id: UUID) async throws -> CallBoard? {
        try await performRead {
            try self.entity(CDCallBoard.self, id: id)?.domainValue()
        }
    }

    func saveBoard(_ board: CallBoard) async throws {
        try await performWrite {
            guard try self.exists(CDWorkspace.self, id: board.workspaceID) else {
                throw RepositoryError.relationshipNotFound(entity: "Workspace", id: board.workspaceID)
            }
            let existingEntity = try self.entity(CDCallBoard.self, id: board.id)
            if let existingEntity, existingEntity.workspaceID != board.workspaceID {
                throw RepositoryError.relationshipConflict(message: "Board workspace cannot be changed.")
            }

            (existingEntity ?? CDCallBoard(context: self.context)).apply(board)
        }
    }

    func deleteBoard(id: UUID) async throws {
        try await performWrite {
            guard let entity = try self.entity(CDCallBoard.self, id: id) else {
                throw RepositoryError.notFound(entity: "CallBoard", id: id)
            }
            guard try self.count(CDCallAction.self, format: "boardID == %@", id) == 0 else {
                throw RepositoryError.relationshipConflict(
                    message: "Cannot delete a board that contains actions."
                )
            }

            self.context.delete(entity)
        }
    }

    func reorderBoards(workspaceID: UUID, orderedIDs: [UUID]) async throws {
        try await performWrite {
            guard try self.exists(CDWorkspace.self, id: workspaceID) else {
                throw RepositoryError.relationshipNotFound(entity: "Workspace", id: workspaceID)
            }
            let currentEntities = try self.entities(CDCallBoard.self, format: "workspaceID == %@", workspaceID)
            try self.applySortOrder(orderedIDs, to: currentEntities, id: \.id) { entity, sortOrder in
                entity.sortOrder = sortOrder
            }
        }
    }

    // MARK: - Actions

    func fetchActions(boardID: UUID, includeDisabled: Bool) async throws -> [CallAction] {
        // Keep the primary calling read independent from any previous
        // repository operation. On iOS 16, a private context can occasionally
        // stop scheduling a later closure even after earlier reads completed.
        // This is a read-only snapshot, so an operation-scoped context is both
        // safe and prevents the calling surface from inheriting that queue.
        let actionReadContext = isolatedReadContext()
        diagnostics.append("ACTION-02 已进入叫号项存储方法")
        return try await performRead(on: actionReadContext) {
            self.diagnostics.append("ACTION-03 叫号项查询闭包已开始")
            let request = NSFetchRequest<CDCallAction>(entityName: "CDCallAction")
            request.predicate = NSPredicate(format: "boardID == %@", boardID as CVarArg)
            let entities = try actionReadContext.fetch(request)
            self.diagnostics.append("ACTION-04 叫号项实体读取完成：\(entities.count) 个")
            let actions = try entities
                .map { try $0.domainValue() }
                .filter { includeDisabled || $0.isEnabled }
            self.diagnostics.append("ACTION-05 叫号项实体转换完成：\(actions.count) 个")
            return RepositoryDataRules.sortedActions(actions)
        }
    }

    func action(id: UUID) async throws -> CallAction? {
        try await performRead {
            try self.entity(CDCallAction.self, id: id)?.domainValue()
        }
    }

    func saveAction(_ action: CallAction) async throws {
        try await performWrite {
            guard try self.exists(CDCallBoard.self, id: action.boardID) else {
                throw RepositoryError.relationshipNotFound(entity: "CallBoard", id: action.boardID)
            }
            if let templateID = action.voiceTemplateID,
               try !self.exists(CDVoiceTemplate.self, id: templateID) {
                throw RepositoryError.relationshipNotFound(entity: "VoiceTemplate", id: templateID)
            }
            let existingEntity = try self.entity(CDCallAction.self, id: action.id)
            if let existingEntity, existingEntity.boardID != action.boardID {
                throw RepositoryError.relationshipConflict(message: "Action board cannot be changed.")
            }

            (existingEntity ?? CDCallAction(context: self.context)).apply(action)
        }
    }

    func deleteAction(id: UUID) async throws {
        try await performWrite {
            guard let entity = try self.entity(CDCallAction.self, id: id) else {
                throw RepositoryError.notFound(entity: "CallAction", id: id)
            }

            self.context.delete(entity)
        }
    }

    func reorderActions(boardID: UUID, orderedIDs: [UUID]) async throws {
        try await performWrite {
            guard try self.exists(CDCallBoard.self, id: boardID) else {
                throw RepositoryError.relationshipNotFound(entity: "CallBoard", id: boardID)
            }
            let currentEntities = try self.entities(CDCallAction.self, format: "boardID == %@", boardID)
            try self.applySortOrder(orderedIDs, to: currentEntities, id: \.id) { entity, sortOrder in
                entity.sortOrder = sortOrder
            }
        }
    }

    // MARK: - Voice templates

    func fetchTemplates(includeBuiltIn: Bool) async throws -> [VoiceTemplate] {
        try await performRead {
            let templates = try self.entities(CDVoiceTemplate.self)
                .map { try $0.domainValue() }
                .filter { includeBuiltIn || !$0.isBuiltIn }
            return RepositoryDataRules.sortedTemplates(templates)
        }
    }

    func template(id: UUID) async throws -> VoiceTemplate? {
        try await performRead {
            try self.entity(CDVoiceTemplate.self, id: id)?.domainValue()
        }
    }

    func saveTemplate(_ template: VoiceTemplate) async throws {
        try await performWrite {
            let existingEntity = try self.entity(CDVoiceTemplate.self, id: template.id)
            if let existingEntity,
               existingEntity.isBuiltIn,
               try existingEntity.domainValue() != template {
                throw RepositoryError.relationshipConflict(message: "Built-in voice templates cannot be modified.")
            }

            (existingEntity ?? CDVoiceTemplate(context: self.context)).apply(template)
        }
    }

    func deleteTemplate(id: UUID) async throws {
        try await performWrite {
            guard let entity = try self.entity(CDVoiceTemplate.self, id: id) else {
                throw RepositoryError.notFound(entity: "VoiceTemplate", id: id)
            }
            guard !entity.isBuiltIn else {
                throw RepositoryError.relationshipConflict(message: "Built-in voice templates cannot be deleted.")
            }
            guard try self.count(CDCallAction.self, format: "voiceTemplateID == %@", id) == 0 else {
                throw RepositoryError.relationshipConflict(
                    message: "Cannot delete a voice template referenced by actions."
                )
            }

            self.context.delete(entity)
        }
    }

    // MARK: - Call records

    func record(id: UUID) async throws -> CallRecord? {
        try await performRead {
            try self.entity(CDCallRecord.self, id: id)?.domainValue()
        }
    }

    func saveRecord(_ record: CallRecord) async throws {
        try await performWrite {
            let existingEntity = try self.entity(CDCallRecord.self, id: record.id)
            if let actionID = record.actionID,
               try !self.exists(CDCallAction.self, id: actionID),
               existingEntity?.actionID != actionID {
                throw RepositoryError.relationshipNotFound(entity: "CallAction", id: actionID)
            }
            if let boardID = record.boardID,
               try !self.exists(CDCallBoard.self, id: boardID),
               existingEntity?.boardID != boardID {
                throw RepositoryError.relationshipNotFound(entity: "CallBoard", id: boardID)
            }

            (existingEntity ?? CDCallRecord(context: self.context)).apply(record)
        }
    }

    func fetchRecords(_ filter: CallHistoryFilter) async throws -> [CallRecord] {
        try await performRead {
            let request = NSFetchRequest<CDCallRecord>(entityName: "CDCallRecord")
            request.predicate = self.recordPredicate(for: filter)
            request.sortDescriptors = [
                NSSortDescriptor(key: "startedAt", ascending: false),
                NSSortDescriptor(key: "id", ascending: true)
            ]
            request.fetchLimit = filter.limit ?? 0
            request.fetchBatchSize = filter.limit ?? 100
            return try self.context.fetch(request).map { try $0.domainValue() }
        }
    }

    func deleteRecords(ids: Set<UUID>) async throws {
        try await performWrite {
            try self.deleteRecordEntities(ids: ids)
        }
    }

    func deleteAllRecords() async throws {
        try await performWrite {
            for entity in try self.entities(CDCallRecord.self) {
                self.context.delete(entity)
            }
        }
    }

    func enforceHistoryRetention(_ policy: HistoryRetentionPolicy, now: Date) async throws -> Int {
        try await performWrite {
            var objectIDsToDelete = Set<NSManagedObjectID>()
            var retainedRecordPredicate: NSPredicate?

            if let retentionDays = policy.retentionDays {
                let cutoff = now.addingTimeInterval(
                    -TimeInterval(retentionDays) * RepositoryDataRules.secondsPerDay
                )
                objectIDsToDelete.formUnion(
                    try self.recordObjectIDs(
                        predicate: NSPredicate(format: "startedAt < %@", cutoff as NSDate)
                    )
                )
                retainedRecordPredicate = NSPredicate(format: "startedAt >= %@", cutoff as NSDate)
            }

            if let maximumRecordCount = policy.maximumRecordCount {
                objectIDsToDelete.formUnion(
                    try self.recordObjectIDs(
                        predicate: retainedRecordPredicate,
                        sortDescriptors: [
                            NSSortDescriptor(key: "startedAt", ascending: false),
                            NSSortDescriptor(key: "id", ascending: true)
                        ],
                        fetchOffset: maximumRecordCount
                    )
                )
            }

            for objectID in objectIDsToDelete {
                self.context.delete(self.context.object(with: objectID))
            }
            return objectIDsToDelete.count
        }
    }

    /// Repairs the obsolete three-digit bundled-audio references created by
    /// the first 钟情小面馆 demo catalog. The fixed board and action IDs keep
    /// this migration from touching a user-created action with the same name.
    func migrateLegacyDemoAudioClipReferences() async throws -> Int {
        try await performWrite {
            let request = NSFetchRequest<CDCallAction>(entityName: "CDCallAction")
            request.predicate = NSPredicate(format: "boardID == %@", CallDeskDemoData.boardID as CVarArg)

            var migratedCount = 0
            for action in try self.context.fetch(request) where CallDeskDemoData.actionIDs.contains(action.id) {
                guard action.playbackModeRawValue == CallActionPlaybackMode.audio.rawValue,
                      let legacyName = action.audioFileName,
                      let currentName = CallDeskDemoData.currentClipName(forLegacyClipName: legacyName) else {
                    continue
                }
                action.audioFileName = currentName
                migratedCount += 1
            }
            return migratedCount
        }
    }

    // MARK: - Initial data

    /// Seeds the base catalog exactly once. Returns `true` when data was
    /// written and `false` when the store already contains data.
    ///
    /// Runs on a background context so a year of demo records never blocks
    /// the main thread at launch; records are saved in batches to keep the
    /// transaction window small. The view context merges changes from its
    /// parent automatically, so the seeded data appears on screen right
    /// after this call finishes.
    func seedInitialDataIfNeeded(catalog: CallDeskSampleData.Catalog) async throws -> Bool {
        diagnostics.append("STORE-20 初始数据写入等待数据库")
        await waitForPersistentStore()
        diagnostics.append("STORE-21 初始数据写入开始")
        let seeded: Bool
        do {
            seeded = try await context.perform {
                let workspaceRequest = NSFetchRequest<CDWorkspace>(entityName: "CDWorkspace")
                let templateRequest = NSFetchRequest<CDVoiceTemplate>(entityName: "CDVoiceTemplate")
                guard try self.context.count(for: workspaceRequest) == 0,
                      try self.context.count(for: templateRequest) == 0 else {
                    return false
                }

                for workspace in catalog.workspaces {
                    CDWorkspace(context: self.context).apply(workspace)
                }
                for board in catalog.boards {
                    CDCallBoard(context: self.context).apply(board)
                }
                for action in catalog.actions {
                    CDCallAction(context: self.context).apply(action)
                }
                for template in catalog.templates {
                    CDVoiceTemplate(context: self.context).apply(template)
                }
                try self.context.save()

                // Call records arrive by the tens of thousands, so they are
                // inserted in batches with a save per batch: one giant
                // transaction would balloon the WAL and stall the device.
                let batchSize = 5_000
                var cursor = 0
                while cursor < catalog.records.count {
                    let batchEnd = min(cursor + batchSize, catalog.records.count)
                    for record in catalog.records[cursor..<batchEnd] {
                        CDCallRecord(context: self.context).apply(record)
                    }
                    try self.context.save()
                    cursor = batchEnd
                }
                return true
            }
        } catch {
            context.rollback()
            assertionFailure("seedInitialDataIfNeeded failed: \(error)")
            throw RepositoryError(wrapping: error)
        }
        return seeded
    }

    // MARK: - Context scheduling

    private func performRead<Value: Sendable>(
        on operationContext: NSManagedObjectContext? = nil,
        _ work: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        diagnostics.append("STORE-10 查询等待数据库就绪")
        do {
            await waitForPersistentStore()
            diagnostics.append("STORE-11 查询进入 Core Data context")
            let scheduledContext = operationContext ?? self.context
            let value = try await scheduledContext.perform {
                do {
                    return try work()
                } catch {
                    throw RepositoryError(wrapping: error)
                }
            }
            diagnostics.append("STORE-13 查询已从 Core Data context 返回")
            return value
        } catch {
            diagnostics.append("STORE-12 查询失败：\(error)")
            throw error
        }
    }

    /// Creates a short-lived private context backed by the same persistent
    /// store coordinator. Domain values leave it before the operation returns,
    /// so it never needs to merge changes into a view context.
    private func isolatedReadContext() -> NSManagedObjectContext {
        guard let coordinator = context.persistentStoreCoordinator else {
            return context
        }
        let isolatedContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        isolatedContext.persistentStoreCoordinator = coordinator
        isolatedContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        return isolatedContext
    }

    func recordDiagnostic(_ message: String) {
        diagnostics.append(message)
    }

    private func performWrite<Value: Sendable>(
        _ work: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        diagnostics.append("STORE-30 写入等待数据库就绪")
        do {
            await waitForPersistentStore()
            diagnostics.append("STORE-31 写入进入 Core Data context")
            return try await context.perform {
                do {
                    let value = try work()
                    if self.context.hasChanges {
                        try self.context.save()
                    }
                    return value
                } catch {
                    self.context.rollback()
                    throw RepositoryError(wrapping: error)
                }
            }
        } catch {
            diagnostics.append("STORE-32 写入失败：\(error)")
            throw error
        }
    }

    // MARK: - Fetch helpers

    private func entity<Entity: NSManagedObject>(_ type: Entity.Type, id: UUID) throws -> Entity? {
        let request = NSFetchRequest<Entity>(entityName: String(describing: type))
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func entities<Entity: NSManagedObject>(
        _ type: Entity.Type,
        format: String? = nil,
        _ argument: UUID? = nil
    ) throws -> [Entity] {
        let request = NSFetchRequest<Entity>(entityName: String(describing: type))
        if let format, let argument {
            request.predicate = NSPredicate(format: format, argument as CVarArg)
        }
        return try context.fetch(request)
    }

    private func count<Entity: NSManagedObject>(
        _ type: Entity.Type,
        format: String? = nil,
        _ argument: UUID? = nil
    ) throws -> Int {
        let request = NSFetchRequest<Entity>(entityName: String(describing: type))
        if let format, let argument {
            request.predicate = NSPredicate(format: format, argument as CVarArg)
        }
        return try context.count(for: request)
    }

    private func exists<Entity: NSManagedObject>(_ type: Entity.Type, id: UUID) throws -> Bool {
        try count(type, format: "id == %@", id) > 0
    }

    private func allDomainWorkspaces() throws -> [Workspace] {
        try entities(CDWorkspace.self).map { try $0.domainValue() }
    }

    private func domainBoards(workspaceID: UUID) throws -> [CallBoard] {
        try entities(CDCallBoard.self, format: "workspaceID == %@", workspaceID)
            .map { try $0.domainValue() }
    }

    private func allDomainRecords() throws -> [CallRecord] {
        try entities(CDCallRecord.self).map { try $0.domainValue() }
    }

    private func recordPredicate(for filter: CallHistoryFilter) -> NSPredicate? {
        var predicates: [NSPredicate] = []
        if let startedFrom = filter.startedFrom {
            predicates.append(NSPredicate(format: "startedAt >= %@", startedFrom as NSDate))
        }
        if let startedThrough = filter.startedThrough {
            predicates.append(NSPredicate(format: "startedAt <= %@", startedThrough as NSDate))
        }
        if let boardID = filter.boardID {
            predicates.append(NSPredicate(format: "boardID == %@", boardID as CVarArg))
        }
        if let actionID = filter.actionID {
            predicates.append(NSPredicate(format: "actionID == %@", actionID as CVarArg))
        }
        if !filter.results.isEmpty {
            predicates.append(
                NSPredicate(format: "resultRawValue IN %@", filter.results.map(\.rawValue))
            )
        }
        if let searchText = filter.searchText {
            predicates.append(
                NSCompoundPredicate(
                    orPredicateWithSubpredicates: [
                        NSPredicate(format: "actionTitleSnapshot CONTAINS[cd] %@", searchText),
                        NSPredicate(format: "spokenTextSnapshot CONTAINS[cd] %@", searchText)
                    ]
                )
            )
        }
        guard !predicates.isEmpty else {
            return nil
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    private func recordObjectIDs(
        predicate: NSPredicate?,
        sortDescriptors: [NSSortDescriptor] = [],
        fetchOffset: Int = 0
    ) throws -> Set<NSManagedObjectID> {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "CDCallRecord")
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors
        request.fetchOffset = fetchOffset
        request.resultType = .managedObjectIDResultType
        return Set(try context.fetch(request).compactMap { $0 as? NSManagedObjectID })
    }

    // MARK: - Shared mutation helpers

    private func applySortOrder<Entity>(
        _ orderedIDs: [UUID],
        to currentEntities: [Entity],
        id: KeyPath<Entity, UUID>,
        update: (Entity, Int64) -> Void
    ) throws {
        let currentIDs = currentEntities.map { $0[keyPath: id] }
        guard RepositoryDataRules.hasExactMembership(currentIDs, orderedIDs: orderedIDs) else {
            throw RepositoryError.invalidReorder
        }

        let entitiesByID = Dictionary(uniqueKeysWithValues: currentEntities.map { ($0[keyPath: id], $0) })
        for (index, entityID) in orderedIDs.enumerated() {
            guard let entity = entitiesByID[entityID] else {
                throw RepositoryError.invalidReorder
            }
            update(entity, Int64(index))
        }
    }

    private func deleteRecordEntities(ids: Set<UUID>) throws {
        guard !ids.isEmpty else {
            return
        }

        let request = NSFetchRequest<CDCallRecord>(entityName: "CDCallRecord")
        request.predicate = NSPredicate(format: "id IN %@", Array(ids) as NSArray)
        for entity in try context.fetch(request) {
            context.delete(entity)
        }
    }
}
