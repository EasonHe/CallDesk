import Foundation

nonisolated struct CallHistoryFilter: Equatable, Sendable {
    static let all = CallHistoryFilter(unchecked: ())

    let startedFrom: Date?
    let startedThrough: Date?
    let boardID: UUID?
    let actionID: UUID?
    let results: Set<CallResult>
    let searchText: String?
    let limit: Int?

    init(
        startedFrom: Date? = nil,
        startedThrough: Date? = nil,
        boardID: UUID? = nil,
        actionID: UUID? = nil,
        results: Set<CallResult> = [],
        searchText: String? = nil,
        limit: Int? = nil
    ) throws {
        if let startedFrom, let startedThrough, startedFrom > startedThrough {
            throw RepositoryError.invalidQuery
        }
        if let limit, limit <= 0 {
            throw RepositoryError.invalidQuery
        }

        self.startedFrom = startedFrom
        self.startedThrough = startedThrough
        self.boardID = boardID
        self.actionID = actionID
        self.results = results
        self.searchText = Self.normalizedSearchText(searchText)
        self.limit = limit
    }

    private init(unchecked: Void) {
        startedFrom = nil
        startedThrough = nil
        boardID = nil
        actionID = nil
        results = []
        searchText = nil
        limit = nil
    }

    private static func normalizedSearchText(_ searchText: String?) -> String? {
        guard let searchText else {
            return nil
        }

        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedSearchText.isEmpty ? nil : trimmedSearchText
    }
}

nonisolated struct HistoryRetentionPolicy: Equatable, Sendable {
    let retentionDays: Int?
    let maximumRecordCount: Int?

    init(retentionDays: Int? = nil, maximumRecordCount: Int? = nil) throws {
        if let retentionDays, retentionDays <= 0 {
            throw RepositoryError.invalidQuery
        }
        if let maximumRecordCount, maximumRecordCount <= 0 {
            throw RepositoryError.invalidQuery
        }

        self.retentionDays = retentionDays
        self.maximumRecordCount = maximumRecordCount
    }
}
