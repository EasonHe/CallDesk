import Foundation

nonisolated struct InMemoryRepositories: Sendable {
    let store: InMemoryCallDeskStore
    let workspaces: InMemoryWorkspaceRepository
    let boards: InMemoryCallBoardRepository
    let actions: InMemoryCallActionRepository
    let templates: InMemoryVoiceTemplateRepository
    let history: InMemoryCallHistoryRepository

    init(store: InMemoryCallDeskStore) {
        self.store = store
        workspaces = InMemoryWorkspaceRepository(store: store)
        boards = InMemoryCallBoardRepository(store: store)
        actions = InMemoryCallActionRepository(store: store)
        templates = InMemoryVoiceTemplateRepository(store: store)
        history = InMemoryCallHistoryRepository(store: store)
    }

    nonisolated static func empty() throws -> InMemoryRepositories {
        InMemoryRepositories(store: try InMemoryCallDeskStore())
    }

    nonisolated static func sample() throws -> InMemoryRepositories {
        let catalog = CallDeskSampleData.catalog
        return InMemoryRepositories(
            store: try InMemoryCallDeskStore(
                workspaces: catalog.workspaces,
                boards: catalog.boards,
                actions: catalog.actions,
                templates: catalog.templates,
                records: catalog.records
            )
        )
    }
}
