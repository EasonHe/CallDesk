import Foundation

nonisolated protocol CallHistoryRepository: Sendable {
    func save(_ record: CallRecord) async throws
    func record(id: UUID) async throws -> CallRecord?
    func fetch(_ filter: CallHistoryFilter) async throws -> [CallRecord]
    func delete(ids: Set<UUID>) async throws
    func deleteAll() async throws
    func enforceRetention(_ policy: HistoryRetentionPolicy, now: Date) async throws -> Int
}
