import Foundation

nonisolated struct ExternalDisplayRecentCardAppearance: Equatable {
    let isHighlighted: Bool
}

nonisolated enum ExternalDisplayRecentCallStyle {
    static func cardAppearance(
        for recentCall: RecentCallPresentation,
        during liveCall: LiveCallState
    ) -> ExternalDisplayRecentCardAppearance {
        ExternalDisplayRecentCardAppearance(
            isHighlighted: isHighlighted(recentCall, during: liveCall)
        )
    }

    static func isHighlighted(
        _ recentCall: RecentCallPresentation,
        during liveCall: LiveCallState
    ) -> Bool {
        guard isActive(liveCall.phase),
              let actionID = recentCall.actionID else {
            return false
        }

        return actionID == liveCall.actionID
    }

    private static func isActive(_ phase: LiveCallPhase) -> Bool {
        switch phase {
        case .queued, .preparing, .playingPrompt, .speaking:
            true
        case .idle, .completed, .cancelled, .interrupted, .failed:
            false
        }
    }
}
