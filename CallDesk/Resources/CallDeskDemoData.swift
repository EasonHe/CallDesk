import Foundation

/// Demo catalog for the "钟情小面馆" showcase store.
///
/// Seeded through the `-calldesk-demo-seed` launch argument when the
/// on-disk database is empty, so the statistics, history and calling
/// screens have realistic data for screenshots. Queue numbers carry no
/// prefix and play bundled audio clips; records cover a full calendar
/// year ending today (starting at January 1st of the previous year), so
/// the twelve-month chart always has data on every day of the year.
nonisolated enum CallDeskDemoData {
    nonisolated static func makeCatalog(now: Date = Date()) -> CallDeskSampleData.Catalog {
        let calendar = Calendar.current
        let yearStart = calendar.date(
            byAdding: .year,
            value: -1,
            to: startOfYear(now)
        ) ?? startOfYear(now)
        let workspace = checked {
            try Workspace(id: workspaceID, name: "钟情小面馆", createdAt: yearStart)
        }
        let boards = [
            checked {
                try CallBoard(
                    id: boardID,
                    workspaceID: workspaceID,
                    name: "钟情小面馆",
                    subtitle: "取餐叫号",
                    sortOrder: 0,
                    createdAt: yearStart
                )
            }
        ]

        var actions: [CallAction] = []
        for (index, number) in queueNumbers.enumerated() {
            actions.append(
                checked {
                    try CallAction(
                        id: actionIDs[index],
                        boardID: boardID,
                        title: number,
                        speechText: "",
                        type: .queueNumber,
                        sortOrder: index,
                        playbackMode: .audio,
                        audioFileName: clipFileNames[index],
                        createdAt: yearStart
                    )
                }
            )
        }

        return CallDeskSampleData.Catalog(
            workspace: workspace,
            boards: boards,
            actions: actions,
            templates: [],
            records: makeRecords(actions: actions, yearStart: yearStart, now: now)
        )
    }

    /// Year-to-date calls: every day issues 60-120 queue tickets called in
    /// ascending order across a lunch peak (11:00-13:30) and a dinner peak
    /// (17:30-20:00), so daily counts vary believably and every chart shows
    /// a natural shape.
    nonisolated private static func makeRecords(actions: [CallAction], yearStart: Date, now: Date) -> [CallRecord] {
        var generator = SeededGenerator(seed: 20_260_807)
        let calendar = Calendar.current
        var records: [CallRecord] = []
        var recordIndex = 0

        var dayStart = yearStart
        while dayStart <= now {
            let ticketCount = Int(generator.intValue(in: 60...120))

            // Each ticket is announced once, plus a recall for roughly one
            // in seven. Timestamps are assigned per call, then calls are
            // replayed in time order with ascending numbers like a real
            // queue.
            var dayEntries: [(timestamp: Date, ticket: Int, recall: Bool)] = []
            for ticket in 1...ticketCount {
                dayEntries.append((timestamp: randomTimestamp(on: dayStart, generator: &generator, calendar: calendar), ticket: ticket, recall: false))
                if generator.intValue(in: 0...6) == 0 {
                    dayEntries.append((timestamp: randomTimestamp(on: dayStart, generator: &generator, calendar: calendar), ticket: ticket, recall: true))
                }
            }
            dayEntries.sort { $0.timestamp < $1.timestamp }

            for entry in dayEntries {
                var startedAt = entry.timestamp
                if startedAt > now {
                    startedAt = now.addingTimeInterval(-Double(generator.intValue(in: 60...1_800)))
                }

                let action = actions[entry.ticket - 1]
                let outcomeRoll = Int(generator.intValue(in: 0...99))
                let repeatIndex = entry.recall ? 1 : 0
                let duration = TimeInterval(generator.intValue(in: 3...8))

                let record: CallRecord
                if outcomeRoll < 95 {
                    record = checked {
                        try CallRecord(
                            id: recordIDs[recordIndex],
                            actionID: action.id,
                            boardID: boardID,
                            actionTitleSnapshot: action.title,
                            spokenTextSnapshot: "请 \(action.title) 号顾客，前来取餐",
                            audioFileNameSnapshot: action.audioFileName,
                            startedAt: startedAt,
                            completedAt: startedAt.addingTimeInterval(duration),
                            result: .completed,
                            repeatIndex: repeatIndex
                        )
                    }
                } else if outcomeRoll < 98 {
                    record = checked {
                        try CallRecord(
                            id: recordIDs[recordIndex],
                            actionID: action.id,
                            boardID: boardID,
                            actionTitleSnapshot: action.title,
                            spokenTextSnapshot: "请 \(action.title) 号顾客，前来取餐",
                            audioFileNameSnapshot: action.audioFileName,
                            startedAt: startedAt,
                            completedAt: startedAt.addingTimeInterval(2),
                            result: .cancelled,
                            repeatIndex: repeatIndex
                        )
                    }
                } else {
                    record = checked {
                        try CallRecord(
                            id: recordIDs[recordIndex],
                            actionID: action.id,
                            boardID: boardID,
                            actionTitleSnapshot: action.title,
                            spokenTextSnapshot: "请 \(action.title) 号顾客，前来取餐",
                            audioFileNameSnapshot: action.audioFileName,
                            startedAt: startedAt,
                            completedAt: startedAt.addingTimeInterval(1),
                            result: .failed,
                            repeatIndex: repeatIndex,
                            errorDescription: "语音输出暂不可用"
                        )
                    }
                }
                records.append(record)
                recordIndex += 1
            }
            dayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? now.addingTimeInterval(86_400)
        }

        return records.sorted { $0.startedAt < $1.startedAt }
    }

    /// Random moment inside one day's service hours: 55% lunch peak,
    /// 35% dinner peak, 10% scattered across the open hours.
    nonisolated private static func randomTimestamp(on dayStart: Date, generator: inout SeededGenerator, calendar: Calendar) -> Date {
        let roll = Int(generator.intValue(in: 0...99))
        let (startHour, startMinute, spanMinutes): (Int, Int, Int)
        if roll < 55 {
            (startHour, startMinute, spanMinutes) = (11, 0, 150)
        } else if roll < 90 {
            (startHour, startMinute, spanMinutes) = (17, 30, 150)
        } else {
            (startHour, startMinute, spanMinutes) = (10, 0, 420)
        }

        let offset = TimeInterval(generator.intValue(in: 0...(spanMinutes - 1)) * 60 + generator.intValue(in: 0...59))
        let anchor = calendar.date(
            bySettingHour: startHour,
            minute: startMinute,
            second: 0,
            of: dayStart
        ) ?? dayStart
        return anchor.addingTimeInterval(offset)
    }

    nonisolated private static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    nonisolated private static func startOfYear(_ date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year], from: date)) ?? startOfDay(date)
    }

    nonisolated private static func checked<T>(_ build: () throws -> T) -> T {
        do { return try build() } catch { preconditionFailure("Invalid CallDesk demo data: \(error)") }
    }

    /// Returns the current bundled name for a legacy three-digit demo clip.
    /// Only 001–099 used a format that no longer matches the bundled files.
    static func currentClipName(forLegacyClipName name: String) -> String? {
        let components = name.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 2,
              components[1] == "mp3",
              components[0].count == 3,
              let number = Int(components[0]),
              (1...99).contains(number) else {
            return nil
        }
        return String(format: "%02d.mp3", number)
    }

    private static let queueNumbers = (1...120).map { String(format: "%03d", $0) }
    /// Bundled clips ship as zero-padded numbers; each queue number plays
    /// the clip that matches it.
    private static let clipFileNames = (1...120).map { String(format: "%02d.mp3", $0) }

    private static let workspaceID = fixedUUID(0, 95)
    static let boardID = fixedUUID(0, 96)
    static let actionIDs = (100...(100 + 119)).map { fixedUUID(0, $0) }
    /// Upper bound covers a full year (366 days) x 120 tickets with recalls.
    private static let recordIDs = (0...(366 * 260)).map { fixedUUID(1, $0) }

    /// Deterministic UUIDs: `group` keeps the action and record ranges
    /// apart, and the 24-bit `value` supports the tens of thousands of
    /// records a full year produces.
    private static func fixedUUID(_ group: Int, _ value: Int) -> UUID {
        UUID(uuid: (
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            UInt8(group & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ))
    }
}

/// Tiny deterministic RNG so every launch seeds the same believable data.
/// Kept free of `RandomNumberGenerator` conformance: the protocol witness is
/// main-actor isolated under Swift 6 and this catalog builds nonisolated.
nonisolated private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 1
    }

    mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func intValue(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(nextUInt64() % UInt64(range.count))
    }
}
