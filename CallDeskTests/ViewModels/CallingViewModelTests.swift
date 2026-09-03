import Combine
import Foundation
import Testing
@testable import CallDesk

@MainActor
@Suite("Calling view model")
struct CallingViewModelTests {
    @Test("Loading selects the first board and exposes its actions")
    func loadSelectsFirstBoardAndExposesActions() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()

        await viewModel.load()

        let content = try #require(loadedContent(of: viewModel))
        #expect(content.workspaceName == "Operations")
        #expect(content.boards.map(\.id) == [Fixture.queueBoardID, Fixture.announcementBoardID])
        #expect(content.selectedBoardID == Fixture.queueBoardID)
        #expect(content.actions.map(\.title) == ["A001", "A002"])
        #expect(content.actions.map(\.isEnabled) == [true, false])
    }

    @Test("Without scenes all boards form a single group")
    func loadExposesAllBoards() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()

        await viewModel.load()

        let content = try #require(loadedContent(of: viewModel))
        #expect(content.boards.map(\.id) == [Fixture.queueBoardID, Fixture.announcementBoardID])
    }

    @Test("Loading without any board reports the empty state")
    func loadWithoutBoardsReportsEmpty() async throws {
        let store = try InMemoryCallDeskStore(
            workspaces: [try Workspace(id: Fixture.workspaceID, name: "Operations")]
        )
        let viewModel = Fixture.makeViewModel(store: store)

        await viewModel.load()

        #expect(viewModel.state == .empty)
    }

    @Test("Scheduled initial loading reaches the empty state without configuration")
    func scheduledInitialLoadWithoutConfigurationReportsEmpty() async throws {
        let viewModel = Fixture.makeViewModel(store: try InMemoryCallDeskStore())

        viewModel.requestRefresh()

        #expect(await waitForEmptyState(of: viewModel))
    }

    @Test("A new empty calling view model loads without a view lifecycle callback")
    func newEmptyViewModelLoadsWithoutLifecycleCallback() async throws {
        let viewModel = Fixture.makeViewModel(store: try InMemoryCallDeskStore())

        #expect(await waitForEmptyState(of: viewModel))
    }

    @Test("A stalled first load exposes its current diagnostic stage")
    func stalledInitialLoadExposesDiagnosticStage() async throws {
        let fixture = try Fixture()
        let repositories = fixture.repositories
        let callService = DefaultCallService(
            actions: repositories.actions,
            history: repositories.history,
            speechDriver: SilentCallSpeechDriver(utteranceDuration: 0)
        )
        let viewModel = CallingViewModel(
            workspaces: DelayedWorkspaceRepository(),
            boards: repositories.boards,
            actions: repositories.actions,
            callService: callService,
            history: repositories.history,
            loadingDiagnosticDelay: .milliseconds(10)
        )

        viewModel.requestRefresh()

        #expect(await waitForDiagnosticStage(.fetchingWorkspaces, of: viewModel))
    }

    @Test("Loading a board without actions stays loaded with no actions")
    func loadBoardWithoutActionsKeepsLoadedState() async throws {
        let store = try InMemoryCallDeskStore(
            workspaces: [try Workspace(id: Fixture.workspaceID, name: "Operations")],
            boards: [
                try CallBoard(
                    id: Fixture.queueBoardID,
                    workspaceID: Fixture.workspaceID,
                    name: "Queue",
                    sortOrder: 0
                )
            ]
        )
        let viewModel = Fixture.makeViewModel(store: store)

        await viewModel.load()

        let content = try #require(loadedContent(of: viewModel))
        #expect(content.selectedBoardID == Fixture.queueBoardID)
        #expect(content.actions.isEmpty)
    }

    @Test("Loading the panel does not wait for restoring the undo target")
    func loadDoesNotWaitForHistoryRestore() async throws {
        let fixture = try Fixture()
        let repositories = fixture.repositories
        let callService = DefaultCallService(
            actions: repositories.actions,
            history: repositories.history,
            speechDriver: SilentCallSpeechDriver(utteranceDuration: 0)
        )
        let viewModel = CallingViewModel(
            workspaces: repositories.workspaces,
            boards: repositories.boards,
            actions: repositories.actions,
            callService: callService,
            history: DelayedHistoryRepository()
        )

        let loadTask = Task {
            await viewModel.refresh()
        }

        #expect(await waitForLoadedContent(of: viewModel))

        loadTask.cancel()
        await loadTask.value
    }

    @Test("Selecting another board replaces the visible actions")
    func selectBoardReplacesVisibleActions() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        await viewModel.selectBoard(id: Fixture.announcementBoardID)

        let content = try #require(loadedContent(of: viewModel))
        #expect(content.selectedBoardID == Fixture.announcementBoardID)
        #expect(content.actions.map(\.title) == ["Pause"])
    }

    @Test("Selecting an unknown board keeps the current content")
    func selectUnknownBoardKeepsCurrentContent() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        await viewModel.selectBoard(id: Fixture.unknownBoardID)

        let content = try #require(loadedContent(of: viewModel))
        #expect(content.selectedBoardID == Fixture.queueBoardID)
    }

    @Test("A repository read failure reports the failed state")
    func repositoryFailureReportsFailedState() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await fixture.store.setFailure(true, for: .fetchAllBoards)

        await viewModel.load()

        #expect(viewModel.state == .failed)
    }

    @Test("Calling an action drives the live call state and writes history")
    func callActionDrivesLiveCallAndWritesHistory() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        await viewModel.callAction(id: Fixture.enabledActionID)

        #expect(viewModel.liveCall == .idle)
        #expect(!viewModel.isCallActive)
        let records = try await fixture.repositories.history.fetch(.all)
        #expect(records.map(\.result) == [.completed])
        #expect(records.first?.actionID == Fixture.enabledActionID)
    }

    @Test("Calling a disabled action does not start a call")
    func callDisabledActionDoesNothing() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        await viewModel.callAction(id: Fixture.disabledActionID)

        #expect(viewModel.liveCall == .idle)
        #expect(try await fixture.repositories.history.fetch(.all).isEmpty)
    }

    @Test("The tile tints immediately when the action is tapped")
    func tileTintsImmediatelyOnTap() async throws {
        let fixture = try Fixture()
        // A slow silent driver keeps the call in flight while we check the
        // tile already reads as pending.
        let repositories = fixture.repositories
        let callService = DefaultCallService(
            actions: repositories.actions,
            history: repositories.history,
            speechDriver: SilentCallSpeechDriver(utteranceDuration: 5)
        )
        let viewModel = CallingViewModel(
            workspaces: repositories.workspaces,
            boards: repositories.boards,
            actions: repositories.actions,
            callService: callService,
            history: repositories.history
        )
        await viewModel.load()

        let callTask = Task {
            await viewModel.callAction(id: Fixture.enabledActionID)
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.isPending(actionID: Fixture.enabledActionID))
        #expect(!viewModel.hasBeenCalled(actionID: Fixture.enabledActionID))

        callTask.cancel()
    }

    @Test("Tapping a pending tile again cancels it and reverts the color")
    func secondTapCancelsPendingCall() async throws {
        let fixture = try Fixture()
        let repositories = fixture.repositories
        let callService = DefaultCallService(
            actions: repositories.actions,
            history: repositories.history,
            speechDriver: SilentCallSpeechDriver(utteranceDuration: 5)
        )
        let viewModel = CallingViewModel(
            workspaces: repositories.workspaces,
            boards: repositories.boards,
            actions: repositories.actions,
            callService: callService,
            history: repositories.history
        )
        await viewModel.load()

        let firstTap = Task {
            await viewModel.callAction(id: Fixture.enabledActionID)
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.isPending(actionID: Fixture.enabledActionID))

        await viewModel.callAction(id: Fixture.enabledActionID)

        #expect(!viewModel.isPending(actionID: Fixture.enabledActionID))
        #expect(!viewModel.hasBeenCalled(actionID: Fixture.enabledActionID))
        #expect(callService.pendingCallCount == 0)
        firstTap.cancel()
    }

    @Test("Tapping a finished tile calls it again")
    func tappingFinishedTileCallsAgain() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        await viewModel.callAction(id: Fixture.enabledActionID)
        #expect(viewModel.hasBeenCalled(actionID: Fixture.enabledActionID))

        await viewModel.callAction(id: Fixture.enabledActionID)

        #expect(viewModel.hasBeenCalled(actionID: Fixture.enabledActionID))
        #expect(viewModel.pendingActionIDs.isEmpty)
        let records = try await fixture.repositories.history.fetch(.all)
        #expect(records.count == 2)
    }

    @Test("Refreshing picks up new boards and keeps the current selection")
    func refreshPicksUpNewBoardsAndKeepsSelection() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()
        await viewModel.selectBoard(id: Fixture.announcementBoardID)

        let newBoard = try CallBoard(
            workspaceID: Fixture.workspaceID,
            name: "Pickup",
            sortOrder: 2
        )
        try await fixture.repositories.boards.save(newBoard)

        await viewModel.refresh()

        let content = try #require(loadedContent(of: viewModel))
        #expect(content.boards.map(\.name) == ["Queue", "Announcements", "Pickup"])
        #expect(content.selectedBoardID == Fixture.announcementBoardID)
    }

    @Test("Refreshing falls back to the first board when the selection was deleted")
    func refreshFallsBackWhenSelectedBoardWasDeleted() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()
        await viewModel.selectBoard(id: Fixture.announcementBoardID)

        try await fixture.repositories.actions.delete(id: Fixture.pauseActionID)
        try await fixture.repositories.boards.delete(id: Fixture.announcementBoardID)

        await viewModel.refresh()

        let content = try #require(loadedContent(of: viewModel))
        #expect(content.boards.map(\.id) == [Fixture.queueBoardID])
        #expect(content.selectedBoardID == Fixture.queueBoardID)
        #expect(content.actions.map(\.title) == ["A001", "A002"])
    }




    @Test("Cancelling a queued tile does not flash its pending tint")
    func cancellingQueuedTileDoesNotFlash() async throws {
        let fixture = try Fixture()
        let repositories = fixture.repositories
        let callService = DefaultCallService(
            actions: repositories.actions,
            history: repositories.history,
            speechDriver: SilentCallSpeechDriver(utteranceDuration: 1)
        )
        let viewModel = CallingViewModel(
            workspaces: repositories.workspaces,
            boards: repositories.boards,
            actions: repositories.actions,
            callService: callService,
            history: repositories.history
        )
        await viewModel.load()
        // The queue board needs a second usable action so one call can be
        // queued behind the other.
        let queuedActionID = UUID()
        try await repositories.actions.save(
            CallAction(
                id: queuedActionID,
                boardID: Fixture.queueBoardID,
                title: "B001",
                speechText: "Please call B001",
                sortOrder: 2
            )
        )
        await viewModel.refresh()

        var sequence: [Set<UUID>] = []
        let subscription = viewModel.$pendingActionIDs.sink { sequence.append($0) }

        let firstTap = Task {
            await viewModel.callAction(id: Fixture.enabledActionID)
        }
        try await Task.sleep(for: .milliseconds(100))
        let secondTap = Task {
            await viewModel.callAction(id: queuedActionID)
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.isPending(actionID: queuedActionID))

        await viewModel.callAction(id: queuedActionID)

        try await Task.sleep(for: .milliseconds(200))
        withExtendedLifetime(subscription) {}
        firstTap.cancel()
        secondTap.cancel()

        let segments = segmentsContaining(sequence, actionID: queuedActionID)
        #expect(segments == 1, "pending tint for the cancelled tile flashed \(segments) times")
    }

    private func segmentsContaining(_ sequence: [Set<UUID>], actionID: UUID) -> Int {
        var segments = 0
        var inSegment = false
        for set in sequence where !set.isEmpty {
            let contains = set.contains(actionID)
            if contains && !inSegment {
                segments += 1
            }
            inSegment = contains
        }
        return segments
    }


    @Test("Loading restores called markers persisted across launches")
    func loadRestoresCalledMarkers() async throws {
        let fixture = try Fixture()
        let markers = InMemoryCalledMarkersStore()
        markers.save([Fixture.enabledActionID])
        let viewModel = fixture.makeViewModel(markers: markers)

        await viewModel.load()

        #expect(viewModel.hasBeenCalled(actionID: Fixture.enabledActionID))
    }

    @Test("A completed call persists its called marker")
    func completedCallPersistsMarker() async throws {
        let fixture = try Fixture()
        let markers = InMemoryCalledMarkersStore()
        let viewModel = fixture.makeViewModel(markers: markers)
        await viewModel.load()

        await viewModel.callAction(id: Fixture.enabledActionID)

        #expect(markers.load() == [Fixture.enabledActionID])
    }

    @Test("Resetting called actions also clears the persisted markers")
    func resetClearsPersistedMarkers() async throws {
        let fixture = try Fixture()
        let markers = InMemoryCalledMarkersStore()
        markers.save([Fixture.enabledActionID])
        let viewModel = fixture.makeViewModel(markers: markers)
        await viewModel.load()
        #expect(viewModel.hasBeenCalled(actionID: Fixture.enabledActionID))

        viewModel.resetCalledActions()

        #expect(!viewModel.hasBeenCalled(actionID: Fixture.enabledActionID))
        #expect(markers.load().isEmpty)
    }

    @Test("Switching boards keeps the called tint")
    func boardSwitchKeepsCalledMarkers() async throws {
        let fixture = try Fixture()
        let markers = InMemoryCalledMarkersStore()
        let viewModel = fixture.makeViewModel(markers: markers)
        await viewModel.load()
        await viewModel.callAction(id: Fixture.enabledActionID)
        #expect(viewModel.hasBeenCalled(actionID: Fixture.enabledActionID))

        await viewModel.selectBoard(id: Fixture.announcementBoardID)

        #expect(viewModel.hasBeenCalled(actionID: Fixture.enabledActionID))
    }

    @Test("An interrupted call surfaces a failure")
    func interruptedCallSurfacesFailure() async throws {
        let fixture = try Fixture()
        let repositories = fixture.repositories
        let audioEnvironment = FixedAudioEnvironmentMonitor()
        let callService = DefaultCallService(
            actions: repositories.actions,
            history: repositories.history,
            speechDriver: SilentCallSpeechDriver(utteranceDuration: 5),
            audioEnvironment: audioEnvironment
        )
        let viewModel = fixture.makeViewModel(callService: callService)
        await viewModel.load()

        let callTask = Task {
            await viewModel.callAction(id: Fixture.enabledActionID)
        }
        try await Task.sleep(for: .milliseconds(100))
        audioEnvironment.reportInterruption(.began)
        await callTask.value

        #expect(viewModel.callOutcomeFailure == .interrupted)
        #expect(!viewModel.hasBeenCalled(actionID: Fixture.enabledActionID))
    }

    @Test("A failed call surfaces a failure and does not mark the tile called")
    func failedCallSurfacesFailure() async throws {
        let fixture = try Fixture()
        let repositories = fixture.repositories
        let callService = DefaultCallService(
            actions: repositories.actions,
            history: repositories.history,
            speechDriver: FailingSpeechDriver()
        )
        let viewModel = fixture.makeViewModel(callService: callService)
        await viewModel.load()

        await viewModel.callAction(id: Fixture.enabledActionID)

        if case .failed = viewModel.callOutcomeFailure {
            // The failure is surfaced for the operator.
        } else {
            Issue.record("expected a failed outcome, got \(String(describing: viewModel.callOutcomeFailure))")
        }
        #expect(!viewModel.hasBeenCalled(actionID: Fixture.enabledActionID))
    }

    @Test("Starting a new call clears a previous failure")
    func newCallClearsPreviousFailure() async throws {
        let fixture = try Fixture()
        let repositories = fixture.repositories
        let audioEnvironment = FixedAudioEnvironmentMonitor()
        let callService = DefaultCallService(
            actions: repositories.actions,
            history: repositories.history,
            speechDriver: SilentCallSpeechDriver(utteranceDuration: 1),
            audioEnvironment: audioEnvironment
        )
        let viewModel = fixture.makeViewModel(callService: callService)
        await viewModel.load()

        let firstCall = Task {
            await viewModel.callAction(id: Fixture.enabledActionID)
        }
        try await Task.sleep(for: .milliseconds(100))
        audioEnvironment.reportInterruption(.began)
        await firstCall.value
        #expect(viewModel.callOutcomeFailure == .interrupted)

        let secondCall = Task {
            await viewModel.callAction(id: Fixture.enabledActionID)
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.callOutcomeFailure == nil)
        await secondCall.value
        #expect(viewModel.callOutcomeFailure == nil)
    }

    @Test("Dismissing clears the failure")
    func dismissClearsFailure() async throws {
        let fixture = try Fixture()
        let repositories = fixture.repositories
        let callService = DefaultCallService(
            actions: repositories.actions,
            history: repositories.history,
            speechDriver: FailingSpeechDriver()
        )
        let viewModel = fixture.makeViewModel(callService: callService)
        await viewModel.load()
        await viewModel.callAction(id: Fixture.enabledActionID)
        guard case .failed = viewModel.callOutcomeFailure else {
            Issue.record("expected a failed outcome, got \(String(describing: viewModel.callOutcomeFailure))")
            return
        }

        viewModel.dismissCallFailure()

        #expect(viewModel.callOutcomeFailure == nil)
    }

    @Test("Progress counts the called actions in the current board")
    func progressCountsCalledActions() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        #expect(viewModel.totalCount == 2)
        #expect(viewModel.calledCount == 0)

        await viewModel.callAction(id: Fixture.enabledActionID)

        #expect(viewModel.calledCount == 1)
        #expect(viewModel.totalCount == 2)
    }

    @Test("Progress is scoped to the selected board")
    func progressIsScopedToSelectedBoard() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()
        await viewModel.callAction(id: Fixture.enabledActionID)

        await viewModel.selectBoard(id: Fixture.announcementBoardID)

        #expect(viewModel.calledCount == 0)
        #expect(viewModel.totalCount == 1)
    }

    @Test("The queue badge is empty while idle")
    func queuedCallCountIsZeroWhenIdle() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        #expect(viewModel.queuedCallCount == 0)
    }

    @Test("The queue badge counts calls waiting behind the active one")
    func queuedCallCountReflectsWaitingCalls() async throws {
        let fixture = try Fixture()
        let repositories = fixture.repositories
        let callService = DefaultCallService(
            actions: repositories.actions,
            history: repositories.history,
            speechDriver: SilentCallSpeechDriver(utteranceDuration: 5)
        )
        let viewModel = fixture.makeViewModel(callService: callService)
        await viewModel.load()
        try await repositories.actions.save(
            CallAction(
                id: Fixture.secondEnabledActionID,
                boardID: Fixture.queueBoardID,
                title: "B001",
                speechText: "Please call B001",
                sortOrder: 2
            )
        )
        await viewModel.refresh()

        let firstTap = Task {
            await viewModel.callAction(id: Fixture.enabledActionID)
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.queuedCallCount == 0)

        let secondTap = Task {
            await viewModel.callAction(id: Fixture.secondEnabledActionID)
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.queuedCallCount == 1)

        firstTap.cancel()
        secondTap.cancel()
    }

    @Test("Selection starts empty and selects the first enabled action")
    func selectionSelectsFirstEnabledAction() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        #expect(viewModel.selectedActionID == nil)

        viewModel.selectNextAction()

        #expect(viewModel.selectedActionID == Fixture.enabledActionID)
    }

    @Test("Select next wraps through the enabled actions")
    func selectNextWrapsThroughEnabledActions() async throws {
        let fixture = try Fixture()
        try await fixture.repositories.actions.save(
            CallAction(
                id: Fixture.secondEnabledActionID,
                boardID: Fixture.queueBoardID,
                title: "B001",
                speechText: "Please call B001",
                sortOrder: 2
            )
        )
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        viewModel.selectNextAction()
        #expect(viewModel.selectedActionID == Fixture.enabledActionID)

        viewModel.selectNextAction()
        #expect(viewModel.selectedActionID == Fixture.secondEnabledActionID)

        viewModel.selectNextAction()
        #expect(viewModel.selectedActionID == Fixture.enabledActionID)
    }

    @Test("Select previous wraps to the last enabled action")
    func selectPreviousWrapsToLastEnabledAction() async throws {
        let fixture = try Fixture()
        try await fixture.repositories.actions.save(
            CallAction(
                id: Fixture.secondEnabledActionID,
                boardID: Fixture.queueBoardID,
                title: "B001",
                speechText: "Please call B001",
                sortOrder: 2
            )
        )
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        viewModel.selectPreviousAction()
        #expect(viewModel.selectedActionID == Fixture.secondEnabledActionID)

        viewModel.selectPreviousAction()
        #expect(viewModel.selectedActionID == Fixture.enabledActionID)
    }

    @Test("Select next skips disabled actions")
    func selectNextSkipsDisabledActions() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        viewModel.selectNextAction()
        #expect(viewModel.selectedActionID == Fixture.enabledActionID)

        viewModel.selectNextAction()

        #expect(viewModel.selectedActionID == Fixture.enabledActionID)
    }

    @Test("Calling the selected action drives a call")
    func callSelectedActionCallsTheSelectedTile() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        viewModel.selectNextAction()
        await viewModel.callSelectedAction()

        #expect(viewModel.hasBeenCalled(actionID: Fixture.enabledActionID))
        let records = try await fixture.repositories.history.fetch(.all)
        #expect(records.map(\.actionID) == [Fixture.enabledActionID])
    }

    @Test("Calling without a selection does nothing")
    func callSelectedActionWithoutSelectionDoesNothing() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        await viewModel.callSelectedAction()

        #expect(try await fixture.repositories.history.fetch(.all).isEmpty)
    }

    @Test("Switching boards clears the keyboard selection")
    func switchingBoardsClearsSelection() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        viewModel.selectNextAction()
        #expect(viewModel.selectedActionID == Fixture.enabledActionID)

        await viewModel.selectBoard(id: Fixture.announcementBoardID)

        #expect(viewModel.selectedActionID == nil)
    }

    @Test("Show action detail follows the settings store")
    func showsActionDetailFollowsSettings() async throws {
        let fixture = try Fixture()
        let settingsStore = InMemorySettingsStore()
        let repositories = fixture.repositories
        let viewModel = CallingViewModel(
            workspaces: repositories.workspaces,
            boards: repositories.boards,
            actions: repositories.actions,
            callService: DefaultCallService(
                actions: repositories.actions,
                history: repositories.history,
                speechDriver: SilentCallSpeechDriver(utteranceDuration: 0)
            ),
            history: repositories.history,
            settingsStore: settingsStore
        )
        #expect(viewModel.showsActionDetail)

        settingsStore.save(
            CallDeskSettings(
                display: try DisplaySettings(recentCallCount: 6, showsActionDetail: false)
            )
        )

        #expect(!viewModel.showsActionDetail)
    }

    @Test("Completing a call sets the last-called action")
    func completedCallSetsLastCalledAction() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        await viewModel.callAction(id: Fixture.enabledActionID)

        #expect(viewModel.lastCalledActionID == Fixture.enabledActionID)
        #expect(viewModel.hasBeenCalled(actionID: Fixture.enabledActionID))
    }

    @Test("Undo deletes the last record and clears the called tint")
    func undoLastCallDeletesRecord() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()
        await viewModel.callAction(id: Fixture.enabledActionID)

        let recordID = try #require(
            try await fixture.repositories.history.fetch(.all).first?.id
        )

        await viewModel.undoCall(for: Fixture.enabledActionID)

        #expect(try await fixture.repositories.history.record(id: recordID) == nil)
        #expect(viewModel.lastCalledActionID == nil)
        #expect(!viewModel.hasBeenCalled(actionID: Fixture.enabledActionID))
    }

    @Test("Undo removes every completed record of today for the number")
    func undoRemovesAllOfTodaysRecords() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        // An accidental double tap produces two completed records for the
        // same number; a single undo must clear both so the daily maximum
        // really drops.
        await viewModel.callAction(id: Fixture.enabledActionID)
        await viewModel.callAction(id: Fixture.enabledActionID)

        let before = try await fixture.repositories.history.fetch(.all)
        #expect(before.filter { $0.actionID == Fixture.enabledActionID }.count == 2)

        await viewModel.undoCall(for: Fixture.enabledActionID)

        let remaining = try await fixture.repositories.history.fetch(.all)
        #expect(!remaining.contains { $0.actionID == Fixture.enabledActionID })
        #expect(!viewModel.hasBeenCalled(actionID: Fixture.enabledActionID))
    }

    @Test("Undo leaves unrelated completed records untouched")
    func undoLeavesOtherRecordsUntouched() async throws {
        let fixture = try Fixture()
        let repositories = fixture.repositories
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        await viewModel.callAction(id: Fixture.enabledActionID)
        // An unrelated record on another board that predates the undo target.
        try await repositories.history.save(
            CallRecord(
                actionID: Fixture.pauseActionID,
                boardID: Fixture.announcementBoardID,
                actionTitleSnapshot: "999",
                spokenTextSnapshot: "999",
                startedAt: .distantPast,
                completedAt: .distantPast.addingTimeInterval(5),
                result: .completed
            )
        )

        await viewModel.undoCall(for: Fixture.enabledActionID)

        let remaining = try await repositories.history.fetch(.all)
        #expect(!remaining.contains { $0.actionTitleSnapshot == "A001" })
        #expect(remaining.contains { $0.actionTitleSnapshot == "999" })
    }

    @Test("Calling the number again after undo records it anew")
    func callingAgainAfterUndoRecordsAnew() async throws {
        let fixture = try Fixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        await viewModel.callAction(id: Fixture.enabledActionID)
        await viewModel.undoCall(for: Fixture.enabledActionID)

        await viewModel.callAction(id: Fixture.enabledActionID)

        #expect(viewModel.hasBeenCalled(actionID: Fixture.enabledActionID))
        #expect(viewModel.lastCalledActionID == Fixture.enabledActionID)
        let records = try await fixture.repositories.history.fetch(.all)
        #expect(records.filter { $0.actionID == Fixture.enabledActionID }.count == 1)
    }

    @Test("Reloading restores the last-called action from history")
    func relaunchRestoresLastCalledAction() async throws {
        let fixture = try Fixture()
        let firstSession = fixture.makeViewModel()
        await firstSession.load()
        await firstSession.callAction(id: Fixture.enabledActionID)

        // A fresh VM over the same store mimics reopening the app: the
        // service bookkeeping is gone, so the undo target must come from
        // persisted history.
        let newSession = fixture.makeViewModel()
        await newSession.load()

        #expect(newSession.lastCalledActionID == Fixture.enabledActionID)
    }

    @Test("Undo works after relaunch using the restored history record")
    func undoWorksAfterRelaunch() async throws {
        let fixture = try Fixture()
        // The marker store is shared between both sessions, mimicking the
        // UserDefaults-backed persistence that keeps the called tint (and
        // therefore undo eligibility) across a real app relaunch.
        let markers = InMemoryCalledMarkersStore()
        let firstSession = fixture.makeViewModel(markers: markers)
        await firstSession.load()
        await firstSession.callAction(id: Fixture.enabledActionID)
        let recordID = try #require(
            try await fixture.repositories.history.fetch(.all).first?.id
        )

        let newSession = fixture.makeViewModel(markers: markers)
        await newSession.load()

        await newSession.undoCall(for: Fixture.enabledActionID)

        #expect(try await fixture.repositories.history.record(id: recordID) == nil)
        #expect(newSession.lastCalledActionID == nil)
        #expect(!newSession.hasBeenCalled(actionID: Fixture.enabledActionID))
    }

    @Test("A relaunch with no completed history keeps the undo target empty")
    func relaunchWithoutHistoryHasNoUndoTarget() async throws {
        let fixture = try Fixture()
        let newSession = fixture.makeViewModel()
        await newSession.load()

        #expect(newSession.lastCalledActionID == nil)
    }

    private func loadedContent(of viewModel: CallingViewModel) -> CallingViewModel.Content? {
        guard case .loaded(let content) = viewModel.state else {
            return nil
        }
        return content
    }

    /// The loading task runs concurrently with this test. Polling the actual
    /// state avoids making the test depend on scheduler timing under a full,
    /// parallel test run.
    private func waitForLoadedContent(of viewModel: CallingViewModel) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while clock.now < deadline {
            if loadedContent(of: viewModel) != nil {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func waitForEmptyState(of viewModel: CallingViewModel) async -> Bool {
        let clock = ContinuousClock()
        // This asserts an eventual state transition, not a one-second
        // performance budget. The full suite launches many Core Data stores
        // concurrently on one simulator, which can briefly delay scheduling.
        let deadline = clock.now.advanced(by: .seconds(3))
        while clock.now < deadline {
            if viewModel.state == .empty {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func waitForDiagnosticStage(
        _ stage: CallingViewModel.LoadingStage,
        of viewModel: CallingViewModel
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while clock.now < deadline {
            if viewModel.loadingDiagnosticStage == stage {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    @MainActor
    private struct Fixture {
        static let workspaceID = fixedUUID(1)
        static let queueBoardID = fixedUUID(2)
        static let announcementBoardID = fixedUUID(3)
        static let unknownBoardID = fixedUUID(99)
        static let enabledActionID = fixedUUID(10)
        static let disabledActionID = fixedUUID(11)
        static let pauseActionID = fixedUUID(12)
        static let secondEnabledActionID = fixedUUID(13)

        let store: InMemoryCallDeskStore
        let repositories: InMemoryRepositories

        init() throws {
            let referenceDate = Date(timeIntervalSinceReferenceDate: 0)
            store = try InMemoryCallDeskStore(
                workspaces: [
                    try Workspace(id: Self.workspaceID, name: "Operations", createdAt: referenceDate)
                ],
                boards: [
                    try CallBoard(
                        id: Self.queueBoardID,
                        workspaceID: Self.workspaceID,
                        name: "Queue",
                        sortOrder: 0,
                        createdAt: referenceDate
                    ),
                    try CallBoard(
                        id: Self.announcementBoardID,
                        workspaceID: Self.workspaceID,
                        name: "Announcements",
                        sortOrder: 1,
                        createdAt: referenceDate
                    )
                ],
                actions: [
                    try CallAction(
                        id: Self.fixedUUID(10),
                        boardID: Self.queueBoardID,
                        title: "A001",
                        speechText: "Please call A001",
                        sortOrder: 0,
                        now: referenceDate
                    ),
                    try CallAction(
                        id: Self.fixedUUID(11),
                        boardID: Self.queueBoardID,
                        title: "A002",
                        speechText: "Please call A002",
                        sortOrder: 1,
                        isEnabled: false,
                        now: referenceDate
                    ),
                    try CallAction(
                        id: Self.fixedUUID(12),
                        boardID: Self.announcementBoardID,
                        title: "Pause",
                        speechText: "Service is paused",
                        sortOrder: 0,
                        now: referenceDate
                    )
                ]
            )
            repositories = InMemoryRepositories(store: store)
        }

        func makeViewModel() -> CallingViewModel {
            Self.makeViewModel(store: store)
        }

        func makeViewModel(markers: any CalledMarkersStoring) -> CallingViewModel {
            let repositories = repositories
            let callService = DefaultCallService(
                actions: repositories.actions,
                history: repositories.history,
                speechDriver: SilentCallSpeechDriver(utteranceDuration: 0)
            )
            return CallingViewModel(
                workspaces: repositories.workspaces,
                boards: repositories.boards,
                actions: repositories.actions,
                callService: callService,
                history: repositories.history,
                calledMarkers: markers
            )
        }

        func makeViewModel(callService: any CallService) -> CallingViewModel {
            let repositories = repositories
            return CallingViewModel(
                workspaces: repositories.workspaces,
                boards: repositories.boards,
                actions: repositories.actions,
                callService: callService,
                history: repositories.history
            )
        }

        static func makeViewModel(store: InMemoryCallDeskStore) -> CallingViewModel {
            let repositories = InMemoryRepositories(store: store)
            let callService = DefaultCallService(
                actions: repositories.actions,
                history: repositories.history,
                speechDriver: SilentCallSpeechDriver(utteranceDuration: 0)
            )
            return CallingViewModel(
                workspaces: repositories.workspaces,
                boards: repositories.boards,
                actions: repositories.actions,
                callService: callService,
                history: repositories.history
            )
        }

        private static func fixedUUID(_ value: UInt8) -> UUID {
            UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
        }
    }
}

private nonisolated struct FailingSpeechDriver: CallSpeechDriving {
    struct DriverError: Error {}

    func announce(
        _ announcement: CallAnnouncement,
        voice: VoiceSettings,
        promptTone: PromptToneSettings
    ) async throws {
        throw DriverError()
    }
}

private nonisolated struct DelayedHistoryRepository: CallHistoryRepository {
    func save(_ record: CallRecord) async throws {}

    func record(id: UUID) async throws -> CallRecord? { nil }

    func fetch(_ filter: CallHistoryFilter) async throws -> [CallRecord] {
        try? await Task.sleep(for: .seconds(10))
        return []
    }

    func delete(ids: Set<UUID>) async throws {}

    func deleteAll() async throws {}

    func enforceRetention(_ policy: HistoryRetentionPolicy, now: Date) async throws -> Int { 0 }
}

private nonisolated struct DelayedWorkspaceRepository: WorkspaceRepository {
    func fetchAll() async throws -> [Workspace] {
        try? await Task.sleep(for: .seconds(10))
        return []
    }

    func workspace(id: UUID) async throws -> Workspace? { nil }

    func save(_ workspace: Workspace) async throws {}

    func delete(id: UUID) async throws {}
}
