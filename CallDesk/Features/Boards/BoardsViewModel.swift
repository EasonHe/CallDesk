import Combine
import Foundation

@MainActor
final class BoardsViewModel: ObservableObject {
    struct Content: Equatable {
        let workspaceID: UUID
        let boards: [CallBoard]
        let actionCounts: [UUID: Int]
    }

    struct Row: Identifiable, Equatable {
        let id: UUID
        let name: String
        let subtitle: String?
        let actionCount: Int
        let isArchived: Bool
    }

    struct BoardDraft: Equatable {
        var name = ""
        var subtitle = ""
        var isArchived = false
    }

    enum OperationError: Equatable {
        case boardContainsActions
        case saveFailed
        case deleteFailed
        case reorderFailed
    }

    @Published private(set) var state: FeatureLoadState<Content> = .loading
    @Published var showsArchived = false
    @Published var operationError: OperationError?

    private let workspaces: any WorkspaceRepository
    private let boards: any CallBoardRepository
    private let actions: any CallActionRepository
    private var hasLoaded = false

    init(
        workspaces: any WorkspaceRepository,
        boards: any CallBoardRepository,
        actions: any CallActionRepository
    ) {
        self.workspaces = workspaces
        self.boards = boards
        self.actions = actions
    }

    convenience init(dependencies: AppDependencies) {
        self.init(
            workspaces: dependencies.workspaces,
            boards: dependencies.boards,
            actions: dependencies.actions
        )
    }

    var hasBoards: Bool {
        guard case .loaded(let content) = state else {
            return false
        }
        return !content.boards.isEmpty
    }

    var visibleRows: [Row] {
        guard case .loaded(let content) = state else {
            return []
        }
        return RepositoryDataRules.sortedBoards(content.boards)
            .filter { showsArchived || !$0.isArchived }
            .map { row(for: $0, in: content) }
    }

    func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }
        await load()
    }

    func load() async {
        hasLoaded = true
        state = .loading
        await reloadContent()
    }

    /// Reloads data without flashing the loading state, so returning from a
    /// detail screen refreshes action counts in place.
    func refresh() async {
        guard hasLoaded else {
            await load()
            return
        }
        await reloadContent()
    }

    func draft(forBoardID id: UUID) -> BoardDraft? {
        guard let board = loadedBoard(id: id) else {
            return nil
        }
        return BoardDraft(
            name: board.name,
            subtitle: board.subtitle ?? "",
            isArchived: board.isArchived
        )
    }

    /// Toggles the archive flag without opening the editor: archiving is a
    /// one-step action, not part of the board's content editing.
    func setArchived(_ isArchived: Bool, boardID: UUID) async {
        guard var draft = draft(forBoardID: boardID) else {
            operationError = .saveFailed
            return
        }
        draft.isArchived = isArchived
        _ = await saveBoard(draft, editingBoardID: boardID)
    }

    @discardableResult
    func saveBoard(_ draft: BoardDraft, editingBoardID: UUID?) async -> Bool {
        guard case .loaded(let content) = state else {
            return await saveFirstBoard(draft)
        }

        do {
            let now = Date()
            if let editingBoardID {
                guard let existing = loadedBoard(id: editingBoardID) else {
                    operationError = .saveFailed
                    return false
                }
                let updated = try CallBoard(
                    id: existing.id,
                    workspaceID: existing.workspaceID,
                    name: draft.name,
                    subtitle: draft.subtitle,
                    sortOrder: existing.sortOrder,
                    preferredColumnCount: existing.preferredColumnCount,
                    showsRecentCalls: existing.showsRecentCalls,
                    isArchived: draft.isArchived,
                    createdAt: existing.createdAt,
                    updatedAt: max(now, existing.createdAt)
                )
                try await boards.save(updated)
            } else {
                let nextSortOrder = content.boards.map(\.sortOrder).max().map { $0 + 1 } ?? 0
                let created = try CallBoard(
                    workspaceID: content.workspaceID,
                    name: draft.name,
                    subtitle: draft.subtitle,
                    sortOrder: nextSortOrder,
                    isArchived: draft.isArchived,
                    createdAt: now
                )
                try await boards.save(created)
            }
            await reloadContent()
            return true
        } catch {
            operationError = .saveFailed
            return false
        }
    }

    /// Saves the very first board of an empty desk. With no sample data on
    /// fresh installs there is no workspace yet, so one is created to host
    /// the board; the save then retries through the regular path.
    private func saveFirstBoard(_ draft: BoardDraft) async -> Bool {
        do {
            if let existing = try await workspaces.fetchAll().first {
                let nextSortOrder = try await boards.fetchAll(
                    workspaceID: existing.id,
                    includeArchived: true
                ).map(\.sortOrder).max().map { $0 + 1 } ?? 0
                try await boards.save(
                    CallBoard(
                        workspaceID: existing.id,
                        name: draft.name,
                        subtitle: draft.subtitle,
                        sortOrder: nextSortOrder,
                        isArchived: draft.isArchived,
                        createdAt: Date()
                    )
                )
                await reloadContent()
                return true
            }

            try await workspaces.save(Workspace(name: "My Desk"))
            await reloadContent()
            return await saveBoard(draft, editingBoardID: nil)
        } catch {
            operationError = .saveFailed
            return false
        }
    }

    func deleteBoard(id: UUID) async {
        do {
            try await boards.delete(id: id)
            await reloadContent()
        } catch RepositoryError.relationshipConflict {
            operationError = .boardContainsActions
        } catch {
            operationError = .deleteFailed
        }
    }

    func moveBoards(from offsets: IndexSet, to destination: Int) async {
        guard case .loaded(let content) = state else {
            return
        }

        let sortedBoards = RepositoryDataRules.sortedBoards(content.boards)
        var visibleBoards = sortedBoards.filter { showsArchived || !$0.isArchived }
        let hiddenBoards = sortedBoards.filter { !showsArchived && $0.isArchived }
        visibleBoards.applyMove(fromOffsets: offsets, toOffset: destination)

        do {
            try await boards.reorder(
                workspaceID: content.workspaceID,
                orderedIDs: visibleBoards.map(\.id) + hiddenBoards.map(\.id)
            )
        } catch {
            operationError = .reorderFailed
        }
        await reloadContent()
    }

    private func reloadContent() async {
        do {
            guard let workspace = try await workspaces.fetchAll().first else {
                state = .empty
                return
            }
            let allBoards = try await boards.fetchAll(
                workspaceID: workspace.id,
                includeArchived: true
            )

            var actionCounts: [UUID: Int] = [:]
            for board in allBoards {
                let boardActions = try await actions.fetch(
                    boardID: board.id,
                    includeDisabled: true
                )
                actionCounts[board.id] = boardActions.count
            }

            state = .loaded(
                Content(
                    workspaceID: workspace.id,
                    boards: allBoards,
                    actionCounts: actionCounts
                )
            )
        } catch {
            state = .failed
        }
    }

    private func row(for board: CallBoard, in content: Content) -> Row {
        Row(
            id: board.id,
            name: board.name,
            subtitle: board.subtitle,
            actionCount: content.actionCounts[board.id] ?? 0,
            isArchived: board.isArchived
        )
    }

    private func loadedBoard(id: UUID) -> CallBoard? {
        guard case .loaded(let content) = state else {
            return nil
        }
        return content.boards.first { $0.id == id }
    }
}
