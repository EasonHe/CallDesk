import Foundation

nonisolated struct InMemoryCallHistoryRepository: CallHistoryRepository {
    private let store: InMemoryCallDeskStore

    init(store: InMemoryCallDeskStore) {
        self.store = store
    }

    func save(_ record: CallRecord) async throws {
        try await store.saveRecord(record)
    }

    func record(id: UUID) async throws -> CallRecord? {
        try await store.record(id: id)
    }

    func fetch(_ filter: CallHistoryFilter) async throws -> [CallRecord] {
        try await store.fetchRecords(filter)
    }

    func delete(ids: Set<UUID>) async throws {
        try await store.deleteRecords(ids: ids)
    }

    func deleteAll() async throws {
        try await store.deleteAllRecords()
    }

    func enforceRetention(_ policy: HistoryRetentionPolicy, now: Date) async throws -> Int {
        try await store.enforceHistoryRetention(policy, now: now)
    }
}
