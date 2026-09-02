import Foundation
import Testing
@testable import CallDesk

@MainActor
@Suite("Boards view model")
struct BoardsViewModelTests {
    @Test("Loading exposes board rows with counts and archive flags")
    func loadBuildsRows() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()

        await viewModel.load()
        viewModel.showsArchived = true

        let rows = viewModel.visibleRows
        #expect(rows.map(\.name) == ["Queue", "Archive Board"])
        #expect(rows[0].subtitle == "Service Hall")
        #expect(rows[0].actionCount == 2)
        #expect(rows[0].isArchived == false)
        #expect(rows[1].actionCount == 0)
        #expect(rows[1].isArchived == true)
    }

    @Test("Archived boards are hidden until showsArchived is enabled")
    func archivedBoardsAreFilteredByToggle() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        #expect(viewModel.visibleRows.map(\.name) == ["Queue"])

        viewModel.showsArchived = true

        #expect(viewModel.visibleRows.map(\.name) == ["Queue", "Archive Board"])
    }

    @Test("setArchived toggles the archive flag without opening the editor")
    func setArchivedTogglesFlag() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()
        viewModel.showsArchived = true

        await viewModel.setArchived(true, boardID: Fixture.queueBoardID)

        #expect(viewModel.operationError == nil)
        let archived = try #require(viewModel.visibleRows.first { $0.id == Fixture.queueBoardID })
        #expect(archived.isArchived == true)

        await viewModel.setArchived(false, boardID: Fixture.queueBoardID)

        let restored = try #require(viewModel.visibleRows.first { $0.id == Fixture.queueBoardID })
        #expect(restored.isArchived == false)
    }

    @Test("setArchived on a missing board surfaces a save error")
    func setArchivedMissingBoardFails() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        await viewModel.setArchived(true, boardID: UUID())

        #expect(viewModel.operationError == .saveFailed)
    }

    @Test("Loading without a workspace reports the empty state")
    func loadWithoutWorkspaceReportsEmpty() async throws {
        let store = try InMemoryCallDeskStore()
        let viewModel = Fixture.makeViewModel(store: store)

        await viewModel.load()

        #expect(viewModel.state == .empty)
    }

    @Test("Loading without boards stays loaded so boards can be created")
    func loadWithoutBoardsStaysLoaded() async throws {
        let store = try InMemoryCallDeskStore(
            workspaces: [try Workspace(id: Fixture.workspaceID, name: "Operations")]
        )
        let viewModel = Fixture.makeViewModel(store: store)

        await viewModel.load()

        #expect(viewModel.hasBoards == false)
        #expect(viewModel.visibleRows.isEmpty)

        let saved = await viewModel.saveBoard(
            BoardsViewModel.BoardDraft(name: "First Board"),
            editingBoardID: nil
        )

        #expect(saved)
        #expect(viewModel.hasBoards)
        #expect(viewModel.visibleRows.map(\.name) == ["First Board"])
    }

    @Test("Saving the first board on an empty desk creates a workspace")
    func savingFirstBoardCreatesWorkspace() async throws {
        let store = try InMemoryCallDeskStore()
        let viewModel = Fixture.makeViewModel(store: store)

        await viewModel.load()
        #expect(viewModel.state == .empty)

        let saved = await viewModel.saveBoard(
            BoardsViewModel.BoardDraft(name: "First Board"),
            editingBoardID: nil
        )

        #expect(saved)
        #expect(viewModel.hasBoards)
        #expect(viewModel.visibleRows.map(\.name) == ["First Board"])
        #expect(try await store.fetchWorkspaces().count == 1)
    }

    @Test("A repository read failure reports the failed state")
    func repositoryFailureReportsFailedState() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await fixture.store.setFailure(true, for: .fetchAllBoards)

        await viewModel.load()

        #expect(viewModel.state == .failed)
        #expect(viewModel.visibleRows.isEmpty)
    }

    @Test("Creating a board appends it after the existing boards")
    func createBoardAppends() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        let saved = await viewModel.saveBoard(
            BoardsViewModel.BoardDraft(
                name: "  Priority  ",
                subtitle: " "
            ),
            editingBoardID: nil
        )

        #expect(saved)
        #expect(viewModel.operationError == nil)
        guard case .loaded(let content) = viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        let created = try #require(content.boards.first { $0.name == "Priority" })
        #expect(created.subtitle == nil)
        #expect(created.sortOrder == 2)
        #expect(viewModel.visibleRows.map(\.name) == ["Queue", "Priority"])
    }

    @Test("Creating a board with a blank name fails with a save error")
    func createBoardWithBlankNameFails() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        let saved = await viewModel.saveBoard(
            BoardsViewModel.BoardDraft(name: "   "),
            editingBoardID: nil
        )

        #expect(saved == false)
        #expect(viewModel.operationError == .saveFailed)
    }

    @Test("Editing a board updates fields while keeping identity and order")
    func editBoardUpdatesFields() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        var draft = try #require(viewModel.draft(forBoardID: Fixture.queueBoardID))
        #expect(draft.name == "Queue")
        #expect(draft.subtitle == "Service Hall")
        #expect(draft.isArchived == false)

        draft.name = "Front Desk"
        draft.subtitle = ""
        draft.isArchived = true

        let saved = await viewModel.saveBoard(draft, editingBoardID: Fixture.queueBoardID)

        #expect(saved)
        guard case .loaded(let content) = viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        let updated = try #require(content.boards.first { $0.id == Fixture.queueBoardID })
        #expect(updated.name == "Front Desk")
        #expect(updated.subtitle == nil)
        #expect(updated.isArchived)
        #expect(updated.sortOrder == 0)
        #expect(updated.createdAt == Fixture.referenceDate)
        #expect(updated.updatedAt >= updated.createdAt)
    }

    @Test("Deleting an empty board removes it from the list")
    func deleteEmptyBoardSucceeds() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()
        viewModel.showsArchived = true

        await viewModel.deleteBoard(id: Fixture.archivedBoardID)

        #expect(viewModel.operationError == nil)
        #expect(viewModel.visibleRows.map(\.name) == ["Queue"])
    }

    @Test("Deleting a board that contains actions surfaces the protection error")
    func deleteBoardWithActionsIsRejected() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        await viewModel.deleteBoard(id: Fixture.queueBoardID)

        #expect(viewModel.operationError == .boardContainsActions)
        #expect(viewModel.visibleRows.contains { $0.id == Fixture.queueBoardID })
    }

    @Test("Moving boards persists the new order")
    func moveBoardsPersistsOrder() async throws {
        let fixture = try Fixture(extraBoardNames: ["Second", "Third"])
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        await viewModel.moveBoards(from: IndexSet(integer: 0), to: 3)

        #expect(viewModel.operationError == nil)
        #expect(viewModel.visibleRows.map(\.name) == ["Second", "Third", "Queue"])
    }

    @Test("Moving boards keeps hidden archived boards in the list")
    func moveBoardsKeepsHiddenArchivedBoards() async throws {
        let fixture = try Fixture(
            extraBoardNames: ["Second"],
            extraArchivedBoardNames: ["Hidden Archive"]
        )
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        await viewModel.moveBoards(from: IndexSet(integer: 0), to: 2)

        #expect(viewModel.operationError == nil)
        #expect(viewModel.visibleRows.map(\.name) == ["Second", "Queue"])

        viewModel.showsArchived = true

        #expect(
            viewModel.visibleRows.map(\.name)
                == ["Second", "Queue", "Archive Board", "Hidden Archive"]
        )
    }

    @Test("A reorder failure surfaces an error and reloads the previous order")
    func moveBoardsFailureSurfacesError() async throws {
        let fixture = try Fixture(extraBoardNames: ["Second"])
        let viewModel = fixture.makeViewModel()
        await viewModel.load()
        await fixture.store.setFailure(true, for: .reorderBoards)

        await viewModel.moveBoards(from: IndexSet(integer: 0), to: 2)

        #expect(viewModel.operationError == .reorderFailed)
        #expect(viewModel.visibleRows.map(\.name) == ["Queue", "Second"])
    }

    @MainActor
    private struct Fixture {
        static let workspaceID = fixedUUID(1)
        static let queueBoardID = fixedUUID(3)
        static let archivedBoardID = fixedUUID(4)
        static let referenceDate = Date(timeIntervalSinceReferenceDate: 0)

        let store: InMemoryCallDeskStore

        init(
            extraBoardNames: [String] = [],
            extraArchivedBoardNames: [String] = []
        ) throws {
            var boards: [CallBoard] = [
                try CallBoard(
                    id: Self.queueBoardID,
                    workspaceID: Self.workspaceID,
                    name: "Queue",
                    subtitle: "Service Hall",
                    sortOrder: 0,
                    createdAt: Self.referenceDate
                ),
                try CallBoard(
                    id: Self.archivedBoardID,
                    workspaceID: Self.workspaceID,
                    name: "Archive Board",
                    sortOrder: 1,
                    isArchived: true,
                    createdAt: Self.referenceDate
                )
            ]

            var nextValue: UInt8 = 20
            for name in extraBoardNames {
                boards.append(
                    try CallBoard(
                        id: Self.fixedUUID(nextValue),
                        workspaceID: Self.workspaceID,
                        name: name,
                        sortOrder: Int(nextValue),
                        createdAt: Self.referenceDate
                    )
                )
                nextValue += 1
            }
            for name in extraArchivedBoardNames {
                boards.append(
                    try CallBoard(
                        id: Self.fixedUUID(nextValue),
                        workspaceID: Self.workspaceID,
                        name: name,
                        sortOrder: Int(nextValue),
                        isArchived: true,
                        createdAt: Self.referenceDate
                    )
                )
                nextValue += 1
            }

            store = try InMemoryCallDeskStore(
                workspaces: [
                    try Workspace(
                        id: Self.workspaceID,
                        name: "Operations",
                        createdAt: Self.referenceDate
                    )
                ],
                boards: boards,
                actions: [
                    try CallAction(
                        id: Self.fixedUUID(10),
                        boardID: Self.queueBoardID,
                        title: "A001",
                        speechText: "Please call A001",
                        sortOrder: 0,
                        now: Self.referenceDate
                    ),
                    try CallAction(
                        id: Self.fixedUUID(11),
                        boardID: Self.queueBoardID,
                        title: "A002",
                        speechText: "Please call A002",
                        sortOrder: 1,
                        isEnabled: false,
                        now: Self.referenceDate
                    )
                ]
            )
        }

        func makeViewModel() -> BoardsViewModel {
            Self.makeViewModel(store: store)
        }

        static func makeViewModel(store: InMemoryCallDeskStore) -> BoardsViewModel {
            let repositories = InMemoryRepositories(store: store)
            return BoardsViewModel(
                workspaces: repositories.workspaces,
                boards: repositories.boards,
                actions: repositories.actions
            )
        }

        private static func fixedUUID(_ value: UInt8) -> UUID {
            UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
        }
    }
}
