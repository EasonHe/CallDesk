import Foundation

/// Sorting, filtering, and retention semantics shared by every CallDesk
/// store implementation, so in-memory and Core Data results stay identical.
nonisolated enum RepositoryDataRules {
    static let secondsPerDay: TimeInterval = 86_400

    static func sortedWorkspaces(_ workspaces: some Sequence<Workspace>) -> [Workspace] {
        workspaces.sorted { lhs, rhs in
            lhs.name == rhs.name ? lhs.id.uuidString < rhs.id.uuidString : lhs.name < rhs.name
        }
    }

    static func sortedBoards(_ boards: some Sequence<CallBoard>) -> [CallBoard] {
        boards.sorted { lhs, rhs in
            lhs.sortOrder == rhs.sortOrder ? lhs.id.uuidString < rhs.id.uuidString : lhs.sortOrder < rhs.sortOrder
        }
    }

    static func sortedActions(_ actions: some Sequence<CallAction>) -> [CallAction] {
        actions.sorted { lhs, rhs in
            lhs.sortOrder == rhs.sortOrder ? lhs.id.uuidString < rhs.id.uuidString : lhs.sortOrder < rhs.sortOrder
        }
    }

    static func sortedTemplates(_ templates: some Sequence<VoiceTemplate>) -> [VoiceTemplate] {
        templates.sorted { lhs, rhs in
            lhs.name == rhs.name ? lhs.id.uuidString < rhs.id.uuidString : lhs.name < rhs.name
        }
    }

    static func sortedRecords(_ records: some Sequence<CallRecord>) -> [CallRecord] {
        records.sorted { lhs, rhs in
            lhs.startedAt == rhs.startedAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.startedAt > rhs.startedAt
        }
    }

    static func hasExactMembership(_ currentIDs: [UUID], orderedIDs: [UUID]) -> Bool {
        currentIDs.count == orderedIDs.count
            && Set(currentIDs) == Set(orderedIDs)
            && Set(orderedIDs).count == orderedIDs.count
    }

    static func matches(_ record: CallRecord, filter: CallHistoryFilter) -> Bool {
        matchesDateRange(record, filter: filter)
            && matchesReferences(record, filter: filter)
            && matchesResult(record, filter: filter)
            && matchesSearchText(record, filter: filter)
    }

    static func retentionDeletionIDs(
        records: [CallRecord],
        policy: HistoryRetentionPolicy,
        now: Date
    ) -> Set<UUID> {
        var recordIDsToDelete = Set<UUID>()
        if let retentionDays = policy.retentionDays {
            let cutoff = now.addingTimeInterval(-TimeInterval(retentionDays) * secondsPerDay)
            recordIDsToDelete.formUnion(
                records.lazy.filter { $0.startedAt < cutoff }.map(\.id)
            )
        }

        let retainedRecords = records.filter { !recordIDsToDelete.contains($0.id) }
        if let maximumRecordCount = policy.maximumRecordCount {
            recordIDsToDelete.formUnion(
                sortedRecords(retainedRecords).dropFirst(maximumRecordCount).map(\.id)
            )
        }
        return recordIDsToDelete
    }

    private static func matchesDateRange(_ record: CallRecord, filter: CallHistoryFilter) -> Bool {
        if let startedFrom = filter.startedFrom, record.startedAt < startedFrom {
            return false
        }
        if let startedThrough = filter.startedThrough, record.startedAt > startedThrough {
            return false
        }
        return true
    }

    private static func matchesReferences(_ record: CallRecord, filter: CallHistoryFilter) -> Bool {
        (filter.boardID == nil || record.boardID == filter.boardID)
            && (filter.actionID == nil || record.actionID == filter.actionID)
    }

    private static func matchesResult(_ record: CallRecord, filter: CallHistoryFilter) -> Bool {
        filter.results.isEmpty || filter.results.contains(record.result)
    }

    private static func matchesSearchText(_ record: CallRecord, filter: CallHistoryFilter) -> Bool {
        guard let searchText = filter.searchText else {
            return true
        }

        return [record.actionTitleSnapshot, record.spokenTextSnapshot]
            .contains { value in
                value.range(of: searchText, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
    }
}
