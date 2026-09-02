import Foundation
import Testing
@testable import CallDesk

@MainActor
@Suite("Board detail view model")
struct BoardDetailViewModelTests {
    @Test("Loading exposes the board and its actions including disabled ones")
    func loadExposesBoardAndActions() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()

        await viewModel.load()

        guard case .loaded(let content) = viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        #expect(content.board.name == "Queue")
        #expect(content.actions.map(\.title) == ["A001", "A002"])
        #expect(content.actions[1].isEnabled == false)
    }

    @Test("Loading an unknown board reports the empty state")
    func loadUnknownBoardReportsEmpty() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel(boardID: Fixture.fixedUUID(99))

        await viewModel.load()

        #expect(viewModel.state == .empty)
    }

    @Test("A repository read failure reports the failed state")
    func repositoryFailureReportsFailedState() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await fixture.store.setFailure(true, for: .fetchActions)

        await viewModel.load()

        #expect(viewModel.state == .failed)
    }

    @Test("Creating an action appends it after the existing actions")
    func createActionAppendsToBoard() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        let saved = await viewModel.saveAction(
            BoardDetailViewModel.ActionDraft(
                title: "  A003  ",
                speechText: "Please call A003",
                style: .success,
                isEnabled: false
            ),
            editingActionID: nil
        )

        #expect(saved)
        #expect(viewModel.operationError == nil)
        guard case .loaded(let content) = viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        #expect(content.actions.map(\.title) == ["A001", "A002", "A003"])
        let created = try #require(content.actions.last)
        #expect(created.style == .success)
        #expect(created.isEnabled == false)
        #expect(created.sortOrder == 2)
        #expect(created.type == .announcement)
    }

    @Test("Creating an action without speech text fails with a save error")
    func createActionWithoutSpeechTextFails() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        let saved = await viewModel.saveAction(
            BoardDetailViewModel.ActionDraft(title: "A003", speechText: "   "),
            editingActionID: nil
        )

        #expect(saved == false)
        #expect(viewModel.operationError == .saveFailed)
    }

    @Test("Batch creation appends prefixed, zero-padded names after existing actions")
    func batchCreationAppendsPrefixedNames() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        let created = await viewModel.createActions(
            batch: BoardDetailViewModel.BatchDraft(
                prefix: "A",
                count: 100,
                startNumber: 1,
                speechTemplate: "",
                style: .success,
                isEnabled: false
            )
        )

        #expect(created)
        guard case .loaded(let content) = viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        let titles = content.actions.map(\.title)
        #expect(titles.count == 102)
        #expect(titles.prefix(2) == ["A001", "A002"])
        #expect(titles[2] == "A01")
        #expect(titles[3] == "A02")
        #expect(titles[11] == "A10")
        #expect(titles.last == "A100")
        let generated = try #require(content.actions.last)
        #expect(generated.speechText == "A100")
        #expect(generated.style == .success)
        #expect(generated.isEnabled == false)
        #expect(generated.sortOrder == 101)
    }

    @Test("Batch creation applies the speech template with the name placeholder")
    func batchCreationAppliesSpeechTemplate() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        let created = await viewModel.createActions(
            batch: BoardDetailViewModel.BatchDraft(
                prefix: "",
                count: 2,
                startNumber: 5,
                speechTemplate: "请，{name} 号，前来取餐。"
            )
        )

        #expect(created)
        guard case .loaded(let content) = viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        let generated = content.actions.suffix(2)
        #expect(generated.map(\.title) == ["05", "06"])
        #expect(generated.map(\.speechText) == [
            "请，05 号，前来取餐。",
            "请，06 号，前来取餐。"
        ])
    }

    @Test("Batch creation accepts the {number} placeholder like the built-in templates")
    func batchCreationAcceptsNumberPlaceholder() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        let created = await viewModel.createActions(
            batch: BoardDetailViewModel.BatchDraft(
                prefix: "A",
                count: 1,
                startNumber: 1,
                speechTemplate: "请，{number} 号，前来取餐。"
            )
        )

        #expect(created)
        guard case .loaded(let content) = viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        let generated = content.actions.suffix(1)
        #expect(generated.map(\.title) == ["A01"])
        #expect(generated.map(\.speechText) == ["请，A01 号，前来取餐。"])
    }

    @Test("Batch draft pre-fills the default announcement template")
    func batchDraftPrefillsDefaultTemplate() {
        let draft = BoardDetailViewModel.BatchDraft()
        #expect(draft.speechTemplate == BoardDetailViewModel.BatchDraft.defaultSpeechTemplate)
        #expect(draft.speechText(for: "01") == "请，01 号，前来取餐。")
    }

    @Test("Batch template half-width punctuation is normalized to full-width Chinese")
    func batchTemplatePunctuationIsNormalized() {
        var draft = BoardDetailViewModel.BatchDraft()
        draft.speechTemplate = "请,{name}号前来取餐."
        #expect(draft.speechText(for: "01") == "请，01号前来取餐。")
        #expect(
            BoardDetailViewModel.BatchDraft.normalizedPunctuation("A!B?C:D(E)")
                == "A！B？C：D（E）"
        )
    }

    @Test("Batch creation with a non-positive count fails")
    func batchCreationRejectsEmptyCount() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        let created = await viewModel.createActions(
            batch: BoardDetailViewModel.BatchDraft(count: 0)
        )

        #expect(created == false)
        #expect(viewModel.operationError == .saveFailed)
    }

    @Test("Editing an action updates fields while preserving identity metadata")
    func editActionPreservesIdentityMetadata() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        var draft = try #require(viewModel.draft(forActionID: Fixture.firstActionID))
        #expect(draft.title == "A001")
        #expect(draft.speechText == "Please call A001")
        #expect(draft.style == .standard)
        #expect(draft.isEnabled)

        draft.title = "B001"
        draft.speechText = "Please call B001"
        draft.style = .warning

        let saved = await viewModel.saveAction(draft, editingActionID: Fixture.firstActionID)

        #expect(saved)
        guard case .loaded(let content) = viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        let updated = try #require(content.actions.first { $0.id == Fixture.firstActionID })
        #expect(updated.title == "B001")
        #expect(updated.speechText == "Please call B001")
        #expect(updated.style == .warning)
        #expect(updated.type == .queueNumber)
        #expect(updated.sortOrder == 0)
        #expect(updated.createdAt == Fixture.referenceDate)
        #expect(updated.updatedAt >= updated.createdAt)
    }

    @Test("Toggling an action's enabled flag persists the change")
    func toggleEnabledPersists() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        await viewModel.setActionEnabled(false, actionID: Fixture.firstActionID)

        #expect(viewModel.operationError == nil)
        guard case .loaded(let content) = viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        let updated = try #require(content.actions.first { $0.id == Fixture.firstActionID })
        #expect(updated.isEnabled == false)

        let persisted = try await InMemoryRepositories(store: fixture.store)
            .actions.action(id: Fixture.firstActionID)
        #expect(persisted?.isEnabled == false)
    }

    @Test("Deleting an action removes it from the board")
    func deleteActionRemovesIt() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        await viewModel.deleteAction(id: Fixture.firstActionID)

        #expect(viewModel.operationError == nil)
        guard case .loaded(let content) = viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        #expect(content.actions.map(\.title) == ["A002"])
    }

    @Test("Moving actions persists the new order")
    func moveActionsPersistsOrder() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        await viewModel.moveActions(from: IndexSet(integer: 0), to: 2)

        #expect(viewModel.operationError == nil)
        guard case .loaded(let content) = viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        #expect(content.actions.map(\.title) == ["A002", "A001"])
        #expect(content.actions.map(\.sortOrder) == [0, 1])
    }

    @Test("A reorder failure surfaces an error and keeps the previous order")
    func moveActionsFailureSurfacesError() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()
        await fixture.store.setFailure(true, for: .reorderActions)

        await viewModel.moveActions(from: IndexSet(integer: 0), to: 2)

        #expect(viewModel.operationError == .reorderFailed)
        guard case .loaded(let content) = viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        #expect(content.actions.map(\.title) == ["A001", "A002"])
    }

    @MainActor
    private struct Fixture {
        static let workspaceID = fixedUUID(1)
        static let boardID = fixedUUID(2)
        static let firstActionID = fixedUUID(10)
        static let secondActionID = fixedUUID(11)
        static let referenceDate = Date(timeIntervalSinceReferenceDate: 0)

        let store: InMemoryCallDeskStore
        let audioPackStore = InMemoryAudioPackStore()

        init() throws {
            store = try InMemoryCallDeskStore(
                workspaces: [
                    try Workspace(
                        id: Self.workspaceID,
                        name: "Operations",
                        createdAt: Self.referenceDate
                    )
                ],
                boards: [
                    try CallBoard(
                        id: Self.boardID,
                        workspaceID: Self.workspaceID,
                        name: "Queue",
                        sortOrder: 0,
                        createdAt: Self.referenceDate
                    )
                ],
                actions: [
                    try CallAction(
                        id: Self.firstActionID,
                        boardID: Self.boardID,
                        title: "A001",
                        speechText: "Please call A001",
                        type: .queueNumber,
                        sortOrder: 0,
                        now: Self.referenceDate
                    ),
                    try CallAction(
                        id: Self.secondActionID,
                        boardID: Self.boardID,
                        title: "A002",
                        speechText: "Please call A002",
                        sortOrder: 1,
                        isEnabled: false,
                        now: Self.referenceDate
                    )
                ]
            )
        }

        func makeViewModel(boardID: UUID = Fixture.boardID) -> BoardDetailViewModel {
            let repositories = InMemoryRepositories(store: store)
            return BoardDetailViewModel(
                boardID: boardID,
                boards: repositories.boards,
                actions: repositories.actions,
                audioClips: FileSystemAudioClipStore(
                    directoryURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                ),
                audioPacks: audioPackStore
            )
        }

        static func fixedUUID(_ value: UInt8) -> UUID {
            UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
        }
    }

    @Test("Batch draft formats titles with trailing digits")
    func batchDraftFormatsTitlesWithTrailingDigits() {
        var draft = BoardDetailViewModel.BatchDraft()
        draft.prefix = "A"
        draft.startNumber = 1
        draft.count = 3

        let name01 = draft.formattedTitle(for: 1)
        let name12 = draft.formattedTitle(for: 12)
        let name123 = draft.formattedTitle(for: 123)
        #expect(name01 == "A01")
        #expect(name12 == "A12")
        #expect(name123 == "A123")
    }

    @Test("Batch creation in audio mode without bundled clips falls back to text")
    func batchAudioModeFallsBackToTextWhenNoBundledClips() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        // Capture the pre-existing action IDs so we can isolate the
        // newly-created batch below.
        guard case .loaded(let before) = viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        let existingIDs = Set(before.actions.map(\.id))

        // Use a prefix whose trailing digits fall outside the bundled
        // clip range so the resolver has nothing to match.
        var draft = BoardDetailViewModel.BatchDraft()
        draft.prefix = "ZZ"
        draft.startNumber = 9001
        draft.count = 3
        draft.playbackMode = .audio

        let created = await viewModel.createActions(batch: draft)
        #expect(created)

        guard case .loaded(let content) = viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        let newActions = content.actions.filter { !existingIDs.contains($0.id) }
        #expect(newActions.count == 3)
        // The title's trailing digits (9001, 9002, 9003) are beyond the
        // bundled pool, so every action degrades to text mode rather than
        // failing the batch entirely.
        #expect(newActions.allSatisfy { $0.playbackMode == .text })
        #expect(newActions.allSatisfy { $0.audioFileName == nil })
    }

    @Test("Batch creation with a picked pack assigns pack clips by number")
    func batchAudioModeAssignsPackClipsByNumber() async throws {
        let fixture = try Fixture()
        let pack = AudioPack(
            id: Fixture.fixedUUID(50),
            name: "Custom",
            createdAt: Fixture.referenceDate,
            clipFileNames: ["01.m4a", "02.m4a", "A10.wav"]
        )
        fixture.audioPackStore.seed(pack)
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        var draft = BoardDetailViewModel.BatchDraft()
        draft.prefix = "A"
        draft.startNumber = 1
        draft.count = 2
        draft.playbackMode = .audio
        draft.audioPackID = pack.id

        let created = await viewModel.createActions(batch: draft)
        #expect(created)

        guard case .loaded(let content) = viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        let generated = content.actions.suffix(2)
        #expect(generated.allSatisfy { $0.playbackMode == .audio })
        #expect(generated.map(\.audioFileName) == [
            "\(pack.id.uuidString)/01.m4a",
            "\(pack.id.uuidString)/02.m4a"
        ])
    }

    @Test("Batch creation with a pack falls back to text for unmatched numbers")
    func batchAudioModeFallsBackToTextForUnmatchedPackNumbers() async throws {
        let fixture = try Fixture()
        let pack = AudioPack(
            id: Fixture.fixedUUID(51),
            name: "Small",
            createdAt: Fixture.referenceDate,
            clipFileNames: ["01.mp3"]
        )
        fixture.audioPackStore.seed(pack)
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        var draft = BoardDetailViewModel.BatchDraft()
        draft.prefix = "A"
        draft.startNumber = 1
        draft.count = 2
        draft.playbackMode = .audio
        draft.audioPackID = pack.id

        let created = await viewModel.createActions(batch: draft)
        #expect(created)

        guard case .loaded(let content) = viewModel.state else {
            Issue.record("Expected a loaded state")
            return
        }
        let generated = Array(content.actions.suffix(2))
        let first = try #require(generated.first)
        let second = try #require(generated.last)
        #expect(first.playbackMode == .audio)
        #expect(first.audioFileName == "\(pack.id.uuidString)/01.mp3")
        // Number 2 has no clip in the pack, so it degrades to text mode.
        #expect(second.playbackMode == .text)
        #expect(second.audioFileName == nil)
    }
}
