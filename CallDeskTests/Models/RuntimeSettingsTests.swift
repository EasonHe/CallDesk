import Foundation
import Testing
@testable import CallDesk

@Suite("Runtime and settings value models")
struct RuntimeSettingsTests {
    private let actionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let boardID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let firstRecentCallID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private let secondRecentCallID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    private let date = Date(timeIntervalSinceReferenceDate: 1_234)

    @Test("Live state retains active-call values")
    func liveStateRetainsActiveCallValues() throws {
        let state = try LiveCallState(
            actionID: actionID,
            boardID: boardID,
            title: "A021",
            spokenText: "Please proceed to counter two.",
            phase: .speaking,
            repeatIndex: 2,
            startedAt: date
        )

        #expect(state.actionID == actionID)
        #expect(state.boardID == boardID)
        #expect(state.title == "A021")
        #expect(state.spokenText == "Please proceed to counter two.")
        #expect(state.phase == .speaking)
        #expect(state.repeatIndex == 2)
        #expect(state.startedAt == date)
    }

    @Test("Live state rejects invalid idle and repeat values")
    func liveStateRejectsInvalidIdleAndRepeatValues() {
        #expect(throws: DomainValidationError.invalidRepeatIndex) {
            try LiveCallState(phase: .queued, repeatIndex: -1)
        }
        #expect(throws: DomainValidationError.invalidStateTransition) {
            try LiveCallState(actionID: actionID, phase: .idle)
        }
    }

    @Test("Idle live state has no stale call data")
    func idleLiveStateHasNoStaleCallData() {
        #expect(LiveCallState.idle.actionID == nil)
        #expect(LiveCallState.idle.boardID == nil)
        #expect(LiveCallState.idle.title == nil)
        #expect(LiveCallState.idle.spokenText == nil)
        #expect(LiveCallState.idle.phase == .idle)
        #expect(LiveCallState.idle.repeatIndex == 0)
        #expect(LiveCallState.idle.startedAt == nil)
    }

    @Test("Audio routes normalize names and identify external outputs")
    func audioRoutesNormalizeNamesAndIdentifyExternalOutputs() throws {
        let route = try AudioRouteDescription(type: .bluetooth, name: " Headset ")

        #expect(route.name == "Headset")
        #expect(route.isExternal)
        #expect(AudioRouteDescription.defaultSpeaker.type == .builtInSpeaker)
        #expect(AudioRouteDescription.defaultSpeaker.name == "Built-in Speaker")
        #expect(AudioRouteDescription.defaultSpeaker.isExternal == false)
        #expect(AudioRouteDescription.unknown.type == .unknown)
        #expect(AudioRouteDescription.unknown.isExternal == false)
    }

    @Test("Audio routes reject blank names")
    func audioRoutesRejectBlankNames() {
        #expect(throws: DomainValidationError.emptyText(field: "name")) {
            try AudioRouteDescription(type: .wired, name: " \n ")
        }
    }

    @Test("Display limiter safely handles nonpositive limits")
    func displayLimiterSafelyHandlesNonpositiveLimits() throws {
        let first = try makeRecentCall(id: firstRecentCallID, calledAt: date)
        let second = try makeRecentCall(
            id: secondRecentCallID,
            calledAt: date.addingTimeInterval(1)
        )
        let state = DisplayPresentationState
            .idle(updatedAt: date)
            .withRecentCalls([first, second])

        #expect(state.limitedRecentCalls(to: 1).recentCalls == [first])
        #expect(state.limitedRecentCalls(to: 0).recentCalls.isEmpty)
        #expect(state.limitedRecentCalls(to: -1).recentCalls.isEmpty)
    }

    @Test("Settings defaults use documented ranges")
    func settingsDefaultsUseDocumentedRanges() throws {
        let settings = CallDeskSettings.default

        #expect(settings.voice.rate == 0.5)
        #expect(settings.voice.pitchMultiplier == 1)
        #expect(settings.voice.volume == 1)
        #expect(!settings.promptTone.isEnabled)
        #expect(settings.promptTone.style == .pickupChime)
        #expect(settings.calling.defaultRepeatCount == 0)
        #expect(settings.calling.repeatDelay == 0)
        #expect(settings.history.retentionDays == 730)
        #expect(settings.history.maximumRecordCount == 20_000)
        #expect(settings.display.recentCallCount == 6)
        #expect(settings.display.restaurantTitle == "美味餐厅")
        #expect(settings.display.showsActionDetail)
    }

    @Test("Display settings decode a legacy payload with the default title")
    func legacyDisplaySettingsUseDefaultRestaurantTitle() throws {
        let decoded = try JSONDecoder().decode(
            DisplaySettings.self,
            from: jsonData("{\"recentCallCount\":6}")
        )

        #expect(decoded.restaurantTitle == "美味餐厅")
        #expect(decoded.showsActionDetail)
    }

    @Test("Display settings decode a payload that turns action detail off")
    func displaySettingsDecodeToggledActionDetail() throws {
        let decoded = try JSONDecoder().decode(
            DisplaySettings.self,
            from: jsonData("{\"recentCallCount\":6,\"showsActionDetail\":false}")
        )

        #expect(!decoded.showsActionDetail)
    }

    @Test("Display settings normalize restaurant titles and reject blanks")
    func displaySettingsNormalizeRestaurantTitleAndRejectBlankValues() throws {
        let settings = try DisplaySettings(recentCallCount: 6, restaurantTitle: " 幸福餐厅 ")

        #expect(settings.restaurantTitle == "幸福餐厅")
        #expect(throws: DomainValidationError.emptyText(field: "restaurantTitle")) {
            try DisplaySettings(recentCallCount: 6, restaurantTitle: " \n ")
        }
        #expect(throws: DomainValidationError.invalidRange(field: "restaurantTitle")) {
            try DisplaySettings(
                recentCallCount: 6,
                restaurantTitle: String(repeating: "餐", count: 25)
            )
        }
    }

    @Test("Settings reject values outside documented ranges")
    func settingsRejectValuesOutsideDocumentedRanges() {
        #expect(throws: DomainValidationError.invalidRange(field: "rate")) {
            try VoiceSettings(localeIdentifier: "en-US", rate: 1.1, pitchMultiplier: 1, volume: 1)
        }
        #expect(throws: DomainValidationError.invalidRange(field: "pitchMultiplier")) {
            try VoiceSettings(localeIdentifier: "en-US", rate: 0.5, pitchMultiplier: 0.4, volume: 1)
        }
        #expect(throws: DomainValidationError.invalidRange(field: "volume")) {
            try VoiceSettings(localeIdentifier: "en-US", rate: 0.5, pitchMultiplier: 1, volume: -0.1)
        }
        #expect(throws: DomainValidationError.invalidRange(field: "defaultRepeatCount")) {
            try CallingSettings(defaultRepeatCount: 6, repeatDelay: 0)
        }
        #expect(throws: DomainValidationError.invalidRange(field: "repeatDelay")) {
            try CallingSettings(defaultRepeatCount: 0, repeatDelay: -0.1)
        }
        #expect(throws: DomainValidationError.invalidRange(field: "recentCallCount")) {
            try DisplaySettings(recentCallCount: 11)
        }
        #expect(throws: DomainValidationError.invalidRange(field: "retentionDays")) {
            try HistorySettings(retentionDays: -1, maximumRecordCount: 5_000)
        }
        #expect(throws: DomainValidationError.invalidRange(field: "maximumRecordCount")) {
            try HistorySettings(retentionDays: 90, maximumRecordCount: -1)
        }
    }

    @Test("Prompt-tone settings decode old payloads with the pickup chime")
    func legacyPromptToneSettingsUsePickupChime() throws {
        let settings = try JSONDecoder().decode(
            PromptToneSettings.self,
            from: jsonData("{\"isEnabled\":true,\"volume\":1,\"delay\":0}")
        )

        #expect(settings.style == .pickupChime)
    }

    @Test("Decoding rejects invalid audio route and settings values")
    func decodingRejectsInvalidAudioRouteAndSettingsValues() {
        let decoder = JSONDecoder()

        #expect(throws: Error.self) {
            try decoder.decode(
                AudioRouteDescription.self,
                from: jsonData("""
                {"type":"wired","name":"   "}
                """)
            )
        }
        #expect(throws: Error.self) {
            try decoder.decode(
                VoiceSettings.self,
                from: jsonData("""
                {"localeIdentifier":"en-US","rate":1.1,"pitchMultiplier":1,"volume":1}
                """)
            )
        }
        #expect(throws: Error.self) {
            try decoder.decode(
                PromptToneSettings.self,
                from: jsonData("""
                {"isEnabled":true,"volume":1,"delay":-0.1}
                """)
            )
        }
        #expect(throws: Error.self) {
            try decoder.decode(
                CallingSettings.self,
                from: jsonData("""
                {"activeSpeechPolicy":"interruptCurrent","defaultRepeatCount":6,"repeatDelay":0}
                """)
            )
        }
        #expect(throws: Error.self) {
            try decoder.decode(
                HistorySettings.self,
                from: jsonData("""
                {"retentionDays":90,"maximumRecordCount":-1}
                """)
            )
        }
        #expect(throws: Error.self) {
            try decoder.decode(
                DisplaySettings.self,
                from: jsonData("""
                {"recentCallCount":11}
                """)
            )
        }
    }

    private func makeRecentCall(id: UUID, calledAt: Date) throws -> RecentCallPresentation {
        try RecentCallPresentation(
            id: id,
            title: "A021",
            spokenText: "Please proceed to counter two.",
            calledAt: calledAt
        )
    }

    private func jsonData(_ text: String) -> Data {
        Data(text.utf8)
    }
}
