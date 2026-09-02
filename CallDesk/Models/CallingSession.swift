import Foundation

/// One accepted calling request while it moves through the calling flow.
nonisolated struct CallingSession: Identifiable, Equatable, Sendable {
    let id: UUID
    let request: CallingRequest
    let startedAt: Date

    init(id: UUID = UUID(), request: CallingRequest, startedAt: Date) {
        self.id = id
        self.request = request
        self.startedAt = startedAt
    }
}
