import Foundation

/// Bundles the Core Data repositories that share one persistent container
/// through a single serialized store.
nonisolated struct CoreDataRepositories: Sendable {
    let store: CoreDataCallDeskStore
    let workspaces: CoreDataWorkspaceRepository
    let boards: CoreDataCallBoardRepository
    let actions: CoreDataCallActionRepository
    let templates: CoreDataVoiceTemplateRepository
    let history: CoreDataCallHistoryRepository

    init(persistence: PersistenceController) {
        let store = CoreDataCallDeskStore(persistence: persistence)
        self.store = store
        workspaces = CoreDataWorkspaceRepository(store: store)
        boards = CoreDataCallBoardRepository(store: store)
        actions = CoreDataCallActionRepository(store: store)
        templates = CoreDataVoiceTemplateRepository(store: store)
        history = CoreDataCallHistoryRepository(store: store)
    }
}
