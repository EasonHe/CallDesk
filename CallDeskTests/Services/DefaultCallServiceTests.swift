import Combine
import Foundation
import Testing
@testable import CallDesk

@MainActor
@Suite("Default call service")
struct DefaultCallServiceTests {
    @Test("A completed call walks the full lifecycle and writes history")
    func completedCallEmitsLifecycleAndWritesHistory() async throws {
        let fixture = try Fixture()
        var phases: [LiveCallPhase] = []
        let subscription = fixture.service.liveCallStatePublisher.sink { state in
            phases.append(state.phase)
        }

        let callTask = Task {
            await fixture.service.requestCall(Fixture.queueRequest)
        }
        await waitUntil("the call is speaking") {
            fixture.service.liveCallState.phase == .speaking
        }
        await fixture.driver.finishNext()
        let result = await callTask.value

        #expect(result == .completed)
        #expect(phases == [.idle, .preparing, .speaking, .completed, .idle])
        #expect(fixture.service.liveCallState == .idle)
        #expect(fixture.service.activeSession == nil)
        #expect(await fixture.driver.spokenTexts == ["Please call A001"])

        let records = try await fixture.repositories.history.fetch(.all)
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.result == .completed)
        #expect(record.actionID == Fixture.enabledActionID)
        #expect(record.boardID == Fixture.boardID)
        #expect(record.actionTitleSnapshot == "A001")
        #expect(record.spokenTextSnapshot == "Please call A001")
        #expect(record.repeatIndex == 0)
        #expect(record.completedAt != nil)
        withExtendedLifetime(subscription) {}
    }

    @Test("A completed call surfaces its record id for undo")
    func completedCallExposesLastCompletedRecordID() async throws {
        let fixture = try Fixture()
        #expect(fixture.service.lastCompletedCallRecordID == nil)

        let callTask = Task {
            await fixture.service.requestCall(Fixture.queueRequest)
        }
        await waitUntil("the call is speaking") {
            fixture.service.liveCallState.phase == .speaking
        }
        await fixture.driver.finishNext()
        let result = await callTask.value

        #expect(result == .completed)
        let recordID = try #require(fixture.service.lastCompletedCallRecordID)
        let records = try await fixture.repositories.history.fetch(.all)
        #expect(records.map(\.id).contains(recordID))
    }

    @Test("The speaking state exposes the action snapshot and session")
    func speakingStateExposesActionSnapshot() async throws {
        let fixture = try Fixture()

        let callTask = Task {
            await fixture.service.requestCall(Fixture.queueRequest)
        }
        await waitUntil("the call is speaking") {
            fixture.service.liveCallState.phase == .speaking
        }

        let state = fixture.service.liveCallState
        #expect(state.actionID == Fixture.enabledActionID)
        #expect(state.boardID == Fixture.boardID)
        #expect(state.title == "A001")
        #expect(state.spokenText == "Please call A001")
        #expect(state.startedAt == Fixture.referenceDate)
        let session = try #require(fixture.service.activeSession)
        #expect(session.request == Fixture.queueRequest)
        #expect(session.startedAt == Fixture.referenceDate)

        await fixture.driver.finishNext()
        _ = await callTask.value
    }

    @Test("Cancelling the active call records a cancelled result")
    func cancelActiveCallRecordsCancelledResult() async throws {
        let fixture = try Fixture()

        let callTask = Task {
            await fixture.service.requestCall(Fixture.queueRequest)
        }
        await waitUntil("the call is speaking") {
            fixture.service.liveCallState.phase == .speaking
        }
        await fixture.service.cancelActiveCall()
        let result = await callTask.value

        #expect(result == .cancelled)
        #expect(fixture.service.liveCallState == .idle)
        #expect(fixture.service.activeSession == nil)

        let records = try await fixture.repositories.history.fetch(.all)
        #expect(records.map(\.result) == [.cancelled])
        #expect(records.first?.completedAt != nil)
    }

    @Test("Cancelling while idle changes nothing")
    func cancelWhileIdleChangesNothing() async throws {
        let fixture = try Fixture()

        await fixture.service.cancelActiveCall()

        #expect(fixture.service.liveCallState == .idle)
        #expect(try await fixture.repositories.history.fetch(.all).isEmpty)
    }

    @Test("The interrupt policy replaces the active call with the new one")
    func interruptPolicyReplacesActiveCall() async throws {
        let fixture = try Fixture()

        let firstTask = Task {
            await fixture.service.requestCall(Fixture.queueRequest)
        }
        await waitUntil("the first call is speaking") {
            fixture.service.liveCallState.phase == .speaking
        }
        let secondTask = Task {
            await fixture.service.requestCall(Fixture.announcementRequest)
        }
        let firstResult = await firstTask.value
        #expect(firstResult == .interrupted)

        await waitUntil("the second call is speaking") {
            fixture.service.liveCallState.title == "Pause"
        }
        await fixture.driver.finishNext()
        let secondResult = await secondTask.value
        #expect(secondResult == .completed)

        let records = try await fixture.repositories.history.fetch(.all)
        #expect(records.count == 2)
        #expect(Set(records.map(\.result)) == [.interrupted, .completed])
    }

    @Test("Cancelling one pending action leaves the others running")
    func cancelOnePendingActionLeavesOthersRunning() async throws {
        let fixture = try Fixture(activeSpeechPolicy: .queueNext)

        let firstTask = Task {
            await fixture.service.requestCall(Fixture.queueRequest)
        }
        await waitUntil("the first call is speaking") {
            fixture.service.liveCallState.phase == .speaking
        }
        let secondTask = Task {
            await fixture.service.requestCall(Fixture.announcementRequest)
        }
        await waitUntil("both calls are pending") {
            fixture.service.pendingCallCount == 2
        }
        #expect(fixture.service.pendingActionIDs == [Fixture.enabledActionID, Fixture.announcementActionID])

        await fixture.service.cancelPendingAction(actionID: Fixture.announcementActionID)

        #expect(await secondTask.value == .cancelled)
        #expect(fixture.service.pendingActionIDs == [Fixture.enabledActionID])

        await fixture.driver.finishNext()
        #expect(await firstTask.value == .completed)

        let records = try await fixture.repositories.history.fetch(.all)
        #expect(records.map(\.result) == [.completed])
    }

    @Test("Cancelling the running action by its ID interrupts it")
    func cancelRunningActionByIDInterruptsIt() async throws {
        let fixture = try Fixture(activeSpeechPolicy: .queueNext)

        let callTask = Task {
            await fixture.service.requestCall(Fixture.queueRequest)
        }
        await waitUntil("the first call is speaking") {
            fixture.service.liveCallState.phase == .speaking
        }

        await fixture.service.cancelPendingAction(actionID: Fixture.enabledActionID)

        #expect(await callTask.value == .cancelled)
        #expect(fixture.service.liveCallState == .idle)
        #expect(fixture.service.pendingActionIDs.isEmpty)
    }

    @Test("The ignore policy rejects a request while a call is active")
    func ignorePolicyRejectsSecondCall() async throws {
        let fixture = try Fixture(activeSpeechPolicy: .ignoreNewCall)

        let callTask = Task {
            await fixture.service.requestCall(Fixture.queueRequest)
        }
        await waitUntil("the call is speaking") {
            fixture.service.liveCallState.phase == .speaking
        }
        let secondResult = await fixture.service.requestCall(Fixture.announcementRequest)
        #expect(secondResult == .ignored)
        #expect(await fixture.driver.spokenTexts.count == 1)

        await fixture.driver.finishNext()
        #expect(await callTask.value == .completed)
        let records = try await fixture.repositories.history.fetch(.all)
        #expect(records.map(\.result) == [.completed])
    }

    @Test("The queue policy runs consecutive calls one after another")
    func queuePolicyRunsCallsSequentially() async throws {
        let fixture = try Fixture(activeSpeechPolicy: .queueNext)

        let firstTask = Task {
            await fixture.service.requestCall(Fixture.queueRequest)
        }
        await waitUntil("the first call is speaking") {
            fixture.service.liveCallState.phase == .speaking
        }
        let secondTask = Task {
            await fixture.service.requestCall(Fixture.announcementRequest)
        }
        await waitUntil("both calls are pending") {
            fixture.service.pendingCallCount == 2
        }
        #expect(await fixture.driver.spokenTexts.count == 1)

        await fixture.driver.finishNext()
        #expect(await firstTask.value == .completed)

        await waitUntil("the queued call is speaking") {
            fixture.service.liveCallState.title == "Pause"
        }
        await fixture.driver.finishNext()
        #expect(await secondTask.value == .completed)

        let records = try await fixture.repositories.history.fetch(.all)
        #expect(records.map(\.result) == [.completed, .completed])
        #expect(await fixture.driver.spokenTexts == ["Please call A001", "Service is paused"])
    }

    @Test("Pending action IDs cover the running and queued calls")
    func pendingActionIDsCoverRunningAndQueuedCalls() async throws {
        let fixture = try Fixture(activeSpeechPolicy: .queueNext)

        let firstTask = Task {
            await fixture.service.requestCall(Fixture.queueRequest)
        }
        await waitUntil("the first call is speaking") {
            fixture.service.liveCallState.phase == .speaking
        }
        let secondTask = Task {
            await fixture.service.requestCall(Fixture.announcementRequest)
        }
        await waitUntil("both calls are pending") {
            fixture.service.pendingCallCount == 2
        }
        await waitUntil("both action IDs are pending") {
            fixture.service.pendingActionIDs == [Fixture.enabledActionID, Fixture.announcementActionID]
        }
        #expect(await fixture.driver.spokenTexts.count == 1)

        await fixture.driver.finishNext()
        await waitUntil("only the queued call is pending") {
            fixture.service.pendingActionIDs == [Fixture.announcementActionID]
        }

        await fixture.driver.finishNext()
        _ = await (firstTask.value, secondTask.value)
        #expect(fixture.service.pendingActionIDs.isEmpty)
    }

    @Test("Cancelling discards queued calls without history entries")
    func cancelDiscardsQueuedCalls() async throws {
        let fixture = try Fixture(activeSpeechPolicy: .queueNext)

        let firstTask = Task {
            await fixture.service.requestCall(Fixture.queueRequest)
        }
        await waitUntil("the first call is speaking") {
            fixture.service.liveCallState.phase == .speaking
        }
        let secondTask = Task {
            await fixture.service.requestCall(Fixture.announcementRequest)
        }
        await waitUntil("both calls are pending") {
            fixture.service.pendingCallCount == 2
        }

        await fixture.service.cancelActiveCall()

        #expect(await firstTask.value == .cancelled)
        #expect(await secondTask.value == .cancelled)
        #expect(fixture.service.liveCallState == .idle)
        #expect(fixture.service.pendingActionIDs.isEmpty)

        let records = try await fixture.repositories.history.fetch(.all)
        #expect(records.map(\.result) == [.cancelled])
    }

    @Test("A missing action fails without writing history")
    func missingActionFailsWithoutHistory() async throws {
        let fixture = try Fixture()

        let result = await fixture.service.requestCall(
            CallingRequest(actionID: Fixture.unknownActionID, boardID: Fixture.boardID)
        )

        #expect(result == .failed(message: "The action no longer exists."))
        #expect(fixture.service.liveCallState == .idle)
        #expect(try await fixture.repositories.history.fetch(.all).isEmpty)
    }

    @Test("A disabled action fails and records the failure")
    func disabledActionFailsWithHistory() async throws {
        let fixture = try Fixture()

        let result = await fixture.service.requestCall(
            CallingRequest(actionID: Fixture.disabledActionID, boardID: Fixture.boardID)
        )

        #expect(result == .failed(message: "The action is disabled."))
        let records = try await fixture.repositories.history.fetch(.all)
        let record = try #require(records.first)
        #expect(record.result == .failed)
        #expect(record.errorDescription == "The action is disabled.")
        #expect(await fixture.driver.spokenTexts.isEmpty)
    }

    @Test("A speech driver failure fails the call and records it")
    func driverFailureRecordsFailedResult() async throws {
        let fixture = try Fixture(driver: FailingSpeechDriver())

        let result = await fixture.service.requestCall(Fixture.queueRequest)

        #expect(result == .failed(message: "Speech playback failed."))
        #expect(fixture.service.liveCallState == .idle)
        let records = try await fixture.repositories.history.fetch(.all)
        let record = try #require(records.first)
        #expect(record.result == .failed)
        #expect(record.errorDescription == "Speech playback failed.")
    }

    @Test("A history write failure does not break a completed call")
    func historyWriteFailureKeepsCallCompleted() async throws {
        let fixture = try Fixture(driver: SilentCallSpeechDriver(utteranceDuration: 0))
        await fixture.store.setFailure(true, for: .saveRecord)

        let result = await fixture.service.requestCall(Fixture.queueRequest)

        #expect(result == .completed)
        #expect(fixture.service.liveCallState == .idle)
        await fixture.store.setFailure(false, for: .saveRecord)
        #expect(try await fixture.repositories.history.fetch(.all).isEmpty)
    }

    @Test("Repeat settings speak the text again and record the repeat index")
    func repeatSettingsSpeakAgain() async throws {
        let fixture = try Fixture(defaultRepeatCount: 1)

        let callTask = Task {
            await fixture.service.requestCall(Fixture.queueRequest)
        }
        await waitUntil("the first utterance is speaking") {
            await fixture.driver.spokenTexts.count == 1
        }
        await fixture.driver.finishNext()
        await waitUntil("the repeat utterance is speaking") {
            await fixture.driver.spokenTexts.count == 2
        }
        #expect(fixture.service.liveCallState.repeatIndex == 1)
        await fixture.driver.finishNext()

        #expect(await callTask.value == .completed)
        let records = try await fixture.repositories.history.fetch(.all)
        #expect(records.first?.repeatIndex == 1)
        #expect(await fixture.driver.spokenTexts == ["Please call A001", "Please call A001"])
    }

    // MARK: - Live settings

    @Test("A policy change applies to the very next request")
    func policyChangeAppliesToNextRequest() async throws {
        let fixture = try Fixture()

        let callTask = Task {
            await fixture.service.requestCall(Fixture.queueRequest)
        }
        await waitUntil("the call is speaking") {
            fixture.service.liveCallState.phase == .speaking
        }
        try fixture.saveSettings(activeSpeechPolicy: .ignoreNewCall)

        let secondResult = await fixture.service.requestCall(Fixture.announcementRequest)
        #expect(secondResult == .ignored)

        await fixture.driver.finishNext()
        #expect(await callTask.value == .completed)
    }

    @Test("A repeat count change applies to the next call")
    func repeatCountChangeAppliesToNextCall() async throws {
        let fixture = try Fixture()

        let firstTask = Task {
            await fixture.service.requestCall(Fixture.queueRequest)
        }
        await waitUntil("the first call is speaking") {
            fixture.service.liveCallState.phase == .speaking
        }
        await fixture.driver.finishNext()
        #expect(await firstTask.value == .completed)
        #expect(await fixture.driver.spokenTexts.count == 1)

        try fixture.saveSettings(defaultRepeatCount: 1)

        let secondTask = Task {
            await fixture.service.requestCall(Fixture.queueRequest)
        }
        await waitUntil("the second call is speaking") {
            await fixture.driver.spokenTexts.count == 2
        }
        await fixture.driver.finishNext()
        await waitUntil("the repeat utterance is speaking") {
            await fixture.driver.spokenTexts.count == 3
        }
        await fixture.driver.finishNext()

        #expect(await secondTask.value == .completed)
        let records = try await fixture.repositories.history.fetch(.all)
        #expect(records.map(\.repeatIndex).contains(1))
    }

    @Test("A running session keeps the settings snapshot it started with")
    func runningSessionKeepsItsSettingsSnapshot() async throws {
        let fixture = try Fixture(defaultRepeatCount: 1)

        let callTask = Task {
            await fixture.service.requestCall(Fixture.queueRequest)
        }
        await waitUntil("the call is speaking") {
            fixture.service.liveCallState.phase == .speaking
        }
        // Dropping the repeat count mid-session must not affect this session.
        try fixture.saveSettings(defaultRepeatCount: 0)

        await fixture.driver.finishNext()
        await waitUntil("the repeat utterance is speaking") {
            await fixture.driver.spokenTexts.count == 2
        }
        await fixture.driver.finishNext()

        #expect(await callTask.value == .completed)
        #expect(await fixture.driver.spokenTexts == ["Please call A001", "Please call A001"])
    }

    @Test("A voice change applies to the next call")
    func voiceChangeAppliesToNextCall() async throws {
        let fixture = try Fixture()

        let firstTask = Task {
            await fixture.service.requestCall(Fixture.queueRequest)
        }
        await waitUntil("the first call is speaking") {
            fixture.service.liveCallState.phase == .speaking
        }
        await fixture.driver.finishNext()
        #expect(await firstTask.value == .completed)

        let japaneseVoice = try VoiceSettings(
            localeIdentifier: "ja-JP",
            rate: 0.5,
            pitchMultiplier: 1,
            volume: 1
        )
        try fixture.saveSettings(voice: japaneseVoice)

        let secondTask = Task {
            await fixture.service.requestCall(Fixture.queueRequest)
        }
        await waitUntil("the second call is speaking") {
            await fixture.driver.spokenLocales.count == 2
        }
        await fixture.driver.finishNext()

        #expect(await secondTask.value == .completed)
        #expect(await fixture.driver.spokenLocales == ["zh-CN", "ja-JP"])
    }

    @Test("A history retention change trims history from the next call on")
    func historyRetentionChangeAppliesToNextCall() async throws {
        let fixture = try Fixture(driver: SilentCallSpeechDriver(utteranceDuration: 0))

        _ = await fixture.service.requestCall(Fixture.queueRequest)
        _ = await fixture.service.requestCall(Fixture.announcementRequest)
        #expect(try await fixture.repositories.history.fetch(.all).count == 2)

        try fixture.saveSettings(
            history: try HistorySettings(retentionDays: 0, maximumRecordCount: 1)
        )

        _ = await fixture.service.requestCall(Fixture.queueRequest)
        let records = try await fixture.repositories.history.fetch(.all)
        #expect(records.count == 1)
    }

    // MARK: - Recalling from history

    @Test("A recall announces the stored snapshot, not the current action")
    func recallAnnouncesTheStoredSnapshot() async throws {
        let fixture = try Fixture()
        // The snapshot deliberately differs from the live action's speech
        // text, so the assertion proves the snapshot wins.
        let record = try makeHistoryRecord(
            actionID: Fixture.enabledActionID,
            boardID: Fixture.boardID,
            speech: "Yesterday's announcement"
        )

        let recallTask = Task { await fixture.service.requestRecall(from: record) }
        await waitUntil("the snapshot is being spoken") {
            await fixture.driver.spokenTexts.count == 1
        }
        await fixture.driver.finishNext()
        let result = await recallTask.value

        #expect(result == .completed)
        let spokenTexts = await fixture.driver.spokenTexts
        #expect(spokenTexts == ["Yesterday's announcement"])
    }

    @Test("A recall still completes when the original action was deleted")
    func recallCompletesWhenTheActionWasDeleted() async throws {
        let fixture = try Fixture(driver: SilentCallSpeechDriver(utteranceDuration: 0))
        let record = try makeHistoryRecord(
            actionID: Fixture.unknownActionID,
            boardID: Fixture.boardID,
            title: "Ghost",
            speech: "Please call the ghost"
        )

        let result = await fixture.service.requestRecall(from: record)

        #expect(result == .completed)
        let records = try await fixture.repositories.history.fetch(.all)
        #expect(records.count == 1)
        let saved = try #require(records.first)
        // The repository rejects links to deleted objects, so the new
        // record is kept as a detached snapshot without identifiers.
        #expect(saved.actionID == nil)
        #expect(saved.boardID == nil)
        #expect(saved.actionTitleSnapshot == "Ghost")
        #expect(saved.spokenTextSnapshot == "Please call the ghost")
        #expect(saved.result == .completed)
    }

    @Test("A recall without identifiers keeps them empty in the new record")
    func recallWithoutIdentifiersKeepsThemEmpty() async throws {
        let fixture = try Fixture(driver: SilentCallSpeechDriver(utteranceDuration: 0))
        let record = try makeHistoryRecord(actionID: nil, boardID: nil)

        let result = await fixture.service.requestRecall(from: record)

        #expect(result == .completed)
        let saved = try #require(try await fixture.repositories.history.fetch(.all).first)
        #expect(saved.actionID == nil)
        #expect(saved.boardID == nil)
    }

    @Test("A recall follows the active speech policy")
    func recallFollowsTheActiveSpeechPolicy() async throws {
        let fixture = try Fixture(activeSpeechPolicy: .ignoreNewCall)
        let record = try makeHistoryRecord(
            actionID: Fixture.enabledActionID,
            boardID: Fixture.boardID
        )

        let callTask = Task { await fixture.service.requestCall(Fixture.queueRequest) }
        await waitUntil("the first call is being spoken") {
            await fixture.driver.spokenTexts.count == 1
        }

        let recallResult = await fixture.service.requestRecall(from: record)
        #expect(recallResult == .ignored)

        await fixture.driver.finishNext()
        _ = await callTask.value
    }

    @Test("A failing recall writes a failed history record")
    func failingRecallWritesFailedRecord() async throws {
        let fixture = try Fixture(driver: FailingSpeechDriver())
        let record = try makeHistoryRecord(
            actionID: Fixture.enabledActionID,
            boardID: Fixture.boardID
        )

        let result = await fixture.service.requestRecall(from: record)

        #expect(result == .failed(message: "Speech playback failed."))
        let saved = try #require(try await fixture.repositories.history.fetch(.all).first)
        #expect(saved.result == .failed)
        #expect(saved.errorDescription == "Speech playback failed.")
    }

    // MARK: - Audio environment

    @Test("A completed call records the current audio route name")
    func completedCallRecordsCurrentAudioRouteName() async throws {
        let fixture = try Fixture()

        let callTask = Task {
            await fixture.service.requestCall(Fixture.queueRequest)
        }
        await waitUntil("the call is speaking") {
            fixture.service.liveCallState.phase == .speaking
        }
        await fixture.driver.finishNext()
        #expect(await callTask.value == .completed)

        let record = try #require(try await fixture.repositories.history.fetch(.all).first)
        #expect(record.audioRouteName == "Built-in Speaker")
    }

    @Test("The next call after a route change records the new route")
    func nextCallAfterRouteChangeRecordsNewRoute() async throws {
        let fixture = try Fixture()

        let firstTask = Task {
            await fixture.service.requestCall(Fixture.queueRequest)
        }
        await waitUntil("the first call is speaking") {
            fixture.service.liveCallState.phase == .speaking
        }
        await fixture.driver.finishNext()
        #expect(await firstTask.value == .completed)

        fixture.audioEnvironment.updateRoute(
            try AudioRouteDescription(type: .bluetooth, name: "Counter Speaker")
        )

        let secondTask = Task {
            await fixture.service.requestCall(Fixture.announcementRequest)
        }
        await waitUntil("the second call is speaking") {
            fixture.service.liveCallState.phase == .speaking
        }
        await fixture.driver.finishNext()
        #expect(await secondTask.value == .completed)

        let records = try await fixture.repositories.history.fetch(.all)
        #expect(records.count == 2)
        let routeNames = records.map(\.audioRouteName)
        #expect(routeNames.contains("Built-in Speaker"))
        #expect(routeNames.contains("Counter Speaker"))
    }

    @Test("An audio interruption ends the active call as interrupted")
    func audioInterruptionEndsActiveCallAsInterrupted() async throws {
        let fixture = try Fixture()

        let callTask = Task {
            await fixture.service.requestCall(Fixture.queueRequest)
        }
        await waitUntil("the call is speaking") {
            fixture.service.liveCallState.phase == .speaking
        }

        fixture.audioEnvironment.reportInterruption(.began)

        #expect(await callTask.value == .interrupted)
        let record = try #require(try await fixture.repositories.history.fetch(.all).first)
        #expect(record.result == .interrupted)
    }

    @Test("The end of an interruption does not restart anything")
    func interruptionEndDoesNotRestartAnything() async throws {
        let fixture = try Fixture()

        fixture.audioEnvironment.reportInterruption(.ended(shouldResume: true))

        #expect(fixture.service.liveCallState == .idle)
        #expect(try await fixture.repositories.history.fetch(.all).isEmpty)
    }

    // MARK: - Helpers

    private func makeHistoryRecord(
        actionID: UUID? = nil,
        boardID: UUID? = nil,
        title: String = "A001",
        speech: String = "Please call A001"
    ) throws -> CallRecord {
        try CallRecord(
            actionID: actionID,
            boardID: boardID,
            actionTitleSnapshot: title,
            spokenTextSnapshot: speech,
            startedAt: Fixture.referenceDate.addingTimeInterval(-60),
            completedAt: Fixture.referenceDate.addingTimeInterval(-59),
            result: .completed
        )
    }

    private func waitUntil(
        _ description: String,
        condition: () async -> Bool
    ) async {
        for _ in 0..<500 {
            if await condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        Issue.record("Timed out waiting until \(description)")
    }

    @MainActor
    private struct Fixture {
        static let workspaceID = fixedUUID(1)
        static let boardID = fixedUUID(2)
        static let enabledActionID = fixedUUID(10)
        static let disabledActionID = fixedUUID(11)
        static let announcementActionID = fixedUUID(12)
        static let unknownActionID = fixedUUID(99)
        static let referenceDate = Date(timeIntervalSinceReferenceDate: 100)

        static let queueRequest = CallingRequest(actionID: enabledActionID, boardID: boardID)
        static let announcementRequest = CallingRequest(
            actionID: announcementActionID,
            boardID: boardID
        )

        let store: InMemoryCallDeskStore
        let repositories: InMemoryRepositories
        let driver: ManualSpeechDriver
        let settingsStore: InMemorySettingsStore
        let audioEnvironment: FixedAudioEnvironmentMonitor
        let service: DefaultCallService

        init(
            activeSpeechPolicy: ActiveSpeechPolicy = .interruptCurrent,
            defaultRepeatCount: Int = 0,
            driver: (any CallSpeechDriving)? = nil
        ) throws {
            let manualDriver = ManualSpeechDriver()
            self.driver = manualDriver
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
                        id: Self.enabledActionID,
                        boardID: Self.boardID,
                        title: "A001",
                        speechText: "Please call A001",
                        sortOrder: 0,
                        now: Self.referenceDate
                    ),
                    try CallAction(
                        id: Self.disabledActionID,
                        boardID: Self.boardID,
                        title: "A002",
                        speechText: "Please call A002",
                        sortOrder: 1,
                        isEnabled: false,
                        now: Self.referenceDate
                    ),
                    try CallAction(
                        id: Self.announcementActionID,
                        boardID: Self.boardID,
                        title: "Pause",
                        speechText: "Service is paused",
                        sortOrder: 2,
                        now: Self.referenceDate
                    )
                ]
            )
            repositories = InMemoryRepositories(store: store)
            let settings = CallDeskSettings(
                calling: try CallingSettings(
                    activeSpeechPolicy: activeSpeechPolicy,
                    defaultRepeatCount: defaultRepeatCount,
                    repeatDelay: 0
                )
            )
            settingsStore = InMemorySettingsStore(settings: settings)
            audioEnvironment = FixedAudioEnvironmentMonitor()
            let referenceDate = Self.referenceDate
            service = DefaultCallService(
                actions: repositories.actions,
                history: repositories.history,
                settingsStore: settingsStore,
                speechDriver: driver ?? manualDriver,
                audioEnvironment: audioEnvironment,
                now: { referenceDate }
            )
        }

        /// Saves new settings mid-test, exactly like the Settings screen does.
        func saveSettings(
            voice: VoiceSettings = .default,
            activeSpeechPolicy: ActiveSpeechPolicy = .interruptCurrent,
            defaultRepeatCount: Int = 0,
            history: HistorySettings = .default
        ) throws {
            settingsStore.save(
                CallDeskSettings(
                    voice: voice,
                    calling: try CallingSettings(
                        activeSpeechPolicy: activeSpeechPolicy,
                        defaultRepeatCount: defaultRepeatCount,
                        repeatDelay: 0
                    ),
                    history: history
                )
            )
        }

        private static func fixedUUID(_ value: UInt8) -> UUID {
            UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
        }
    }
}

/// A speech driver that stays inside `speak` until the test finishes it.
private actor ManualSpeechDriver: CallSpeechDriving {
    private(set) var spokenTexts: [String] = []
    private(set) var spokenLocales: [String] = []
    private(set) var spokenPromptTones: [PromptToneSettings] = []
    private var pending: [UUID: CheckedContinuation<Void, any Error>] = [:]

    func announce(_ announcement: CallAnnouncement, voice: VoiceSettings, promptTone: PromptToneSettings) async throws {
        switch announcement {
        case .speech(let text):
            spokenTexts.append(text)
        case .audio(let url):
            spokenTexts.append(url.lastPathComponent)
        }
        spokenLocales.append(voice.localeIdentifier)
        spokenPromptTones.append(promptTone)
        let utteranceID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    pending[utteranceID] = continuation
                }
            }
        } onCancel: {
            Task {
                await self.cancelUtterance(id: utteranceID)
            }
        }
    }

    func finishNext() {
        guard !pending.isEmpty else {
            return
        }
        let utteranceID = pending.keys.sorted { $0.uuidString < $1.uuidString }[0]
        pending.removeValue(forKey: utteranceID)?.resume()
    }

    private func cancelUtterance(id: UUID) {
        pending.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
}

private nonisolated struct FailingSpeechDriver: CallSpeechDriving {
    struct DriverError: Error {}

    func announce(_ announcement: CallAnnouncement, voice: VoiceSettings, promptTone: PromptToneSettings) async throws {
        throw DriverError()
    }
}
