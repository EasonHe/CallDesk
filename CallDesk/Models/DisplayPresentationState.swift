import Foundation

nonisolated struct RecentCallPresentation: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let actionID: UUID?
    let title: String
    let spokenText: String
    let calledAt: Date

    init(
        id: UUID,
        actionID: UUID? = nil,
        title: String,
        spokenText: String,
        calledAt: Date
    ) throws {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw DomainValidationError.emptyName(field: "title")
        }

        let normalizedSpokenText = spokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSpokenText.isEmpty else {
            throw DomainValidationError.emptyText(field: "spokenText")
        }

        self.id = id
        self.actionID = actionID
        self.title = normalizedTitle
        self.spokenText = normalizedSpokenText
        self.calledAt = calledAt
    }
}

nonisolated struct DisplayPresentationState: Equatable, Sendable {
    let liveCall: LiveCallState
    let recentCalls: [RecentCallPresentation]
    let updatedAt: Date

    static func idle(updatedAt: Date) -> DisplayPresentationState {
        DisplayPresentationState(
            liveCall: .idle,
            recentCalls: [],
            updatedAt: updatedAt
        )
    }

    init(
        liveCall: LiveCallState,
        recentCalls: [RecentCallPresentation] = [],
        updatedAt: Date
    ) {
        self.liveCall = liveCall
        self.recentCalls = recentCalls
        self.updatedAt = updatedAt
    }

    func withRecentCalls(_ recentCalls: [RecentCallPresentation]) -> DisplayPresentationState {
        DisplayPresentationState(
            liveCall: liveCall,
            recentCalls: recentCalls,
            updatedAt: updatedAt
        )
    }

    func limitedRecentCalls(to maximumCount: Int) -> DisplayPresentationState {
        guard maximumCount > 0 else {
            return withRecentCalls([])
        }

        return withRecentCalls(Array(recentCalls.prefix(maximumCount)))
    }
}
