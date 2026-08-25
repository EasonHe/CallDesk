import Foundation
import Testing
@testable import CallDesk

@Suite("External display recent call styling")
struct ExternalDisplayRecentCallStyleTests {
    @Test("A matching recent action is highlighted during an active call")
    func matchingRecentActionIsHighlightedDuringActiveCall() throws {
        let actionID = UUID()
        let recentCall = try makeRecentCall(actionID: actionID)
        let liveCall = try makeLiveCall(actionID: actionID, phase: .speaking)

        #expect(ExternalDisplayRecentCallStyle.isHighlighted(recentCall, during: liveCall))
    }

    @Test("A nonmatching recent action is not highlighted")
    func nonmatchingRecentActionIsNotHighlighted() throws {
        let recentCall = try makeRecentCall(actionID: UUID())
        let liveCall = try makeLiveCall(actionID: UUID(), phase: .speaking)

        #expect(!ExternalDisplayRecentCallStyle.isHighlighted(recentCall, during: liveCall))
    }

    @Test("A recent call without an action identifier is not highlighted")
    func recentCallWithoutActionIdentifierIsNotHighlighted() throws {
        let actionID = UUID()
        let recentCall = try makeRecentCall(actionID: nil)
        let liveCall = try makeLiveCall(actionID: actionID, phase: .speaking)

        #expect(!ExternalDisplayRecentCallStyle.isHighlighted(recentCall, during: liveCall))
    }

    @Test("Idle and completed calls do not highlight a matching recent action")
    func inactiveCallsDoNotHighlightMatchingRecentAction() throws {
        let actionID = UUID()
        let recentCall = try makeRecentCall(actionID: actionID)
        let completedCall = try makeLiveCall(actionID: actionID, phase: .completed)

        #expect(!ExternalDisplayRecentCallStyle.isHighlighted(recentCall, during: .idle))
        #expect(!ExternalDisplayRecentCallStyle.isHighlighted(recentCall, during: completedCall))
    }

    @Test("A matching action follows the complete live-call phase table")
    func matchingActionFollowsLiveCallPhaseTable() throws {
        let actionID = UUID()
        let recentCall = try makeRecentCall(actionID: actionID)
        let phaseExpectations: [(LiveCallPhase, Bool)] = [
            (.queued, true),
            (.preparing, true),
            (.playingPrompt, true),
            (.speaking, true),
            (.idle, false),
            (.completed, false),
            (.cancelled, false),
            (.interrupted, false),
            (.failed(message: "Unable to speak"), false)
        ]

        for (phase, expectedHighlight) in phaseExpectations {
            let liveCall = if phase == .idle {
                LiveCallState.idle
            } else {
                try makeLiveCall(actionID: actionID, phase: phase)
            }

            #expect(
                ExternalDisplayRecentCallStyle.isHighlighted(recentCall, during: liveCall)
                    == expectedHighlight
            )
        }
    }

    @Test("Recent-card appearance highlights only the matching active call")
    func recentCardAppearanceHighlightsOnlyMatchingActiveCall() throws {
        let matchingActionID = UUID()
        let matching = try makeRecentCall(actionID: matchingActionID)
        let other = try makeRecentCall(actionID: UUID())
        let liveCall = try makeLiveCall(actionID: matchingActionID, phase: .speaking)

        #expect(
            ExternalDisplayRecentCallStyle
                .cardAppearance(for: matching, during: liveCall)
                .isHighlighted
        )
        #expect(
            !ExternalDisplayRecentCallStyle
                .cardAppearance(for: other, during: liveCall)
                .isHighlighted
        )
    }

    private func makeRecentCall(actionID: UUID?) throws -> RecentCallPresentation {
        try RecentCallPresentation(
            id: UUID(),
            actionID: actionID,
            title: "A001",
            spokenText: "请 A001 前来取餐",
            calledAt: Date(timeIntervalSinceReferenceDate: 0)
        )
    }

    private func makeLiveCall(actionID: UUID, phase: LiveCallPhase) throws -> LiveCallState {
        try LiveCallState(
            actionID: actionID,
            title: "A001",
            spokenText: "请 A001 前来取餐",
            phase: phase,
            startedAt: Date(timeIntervalSinceReferenceDate: 0)
        )
    }
}
