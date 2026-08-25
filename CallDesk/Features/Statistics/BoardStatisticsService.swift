import Foundation

nonisolated enum BoardStatisticsService {
    struct DayCount: Equatable, Sendable {
        let day: Date
        let count: Int
    }

    /// The served count of one calendar week, keyed by its Monday.
    struct WeekCount: Equatable, Sendable {
        let weekStart: Date
        let count: Int
    }

    /// The served count of one calendar month, keyed by its first day.
    struct MonthCount: Equatable, Sendable {
        let monthStart: Date
        let count: Int
    }

    struct PeriodComparison: Equatable, Sendable {
        let recent: Int
        let earlier: Int
        let percentage: Int?
    }

    /// The hour window that served the most distinct queue numbers,
    /// e.g. 11:00–12:00. Repeated calls of one number count once.
    struct PeakHour: Equatable, Sendable {
        let hour: Int
        let servedCount: Int
    }

    struct WeekStats: Equatable, Sendable {
        let weeklyCount: Int
        let dailyCounts: [DayCount]
        let weeklyCounts: [WeekCount]
        let comparison: PeriodComparison?
        let peakHour: PeakHour?
        /// Average served count per week over the trailing eight weeks.
        let weeklyAverage: Double
        let singleDayHigh: Int
    }

    struct MonthStats: Equatable, Sendable {
        let monthlyCount: Int
        let dailyCounts: [DayCount]
        let monthlyCounts: [MonthCount]
        let comparison: PeriodComparison?
        let peakHour: PeakHour?
        /// Average served count per month over the trailing twelve months.
        let monthlyAverage: Double
        let singleDayHigh: Int
    }

    struct YearStats: Equatable, Sendable {
        let yearlyCount: Int
        let monthlyCounts: [MonthCount]
        let peakHour: PeakHour?
        let monthlyAverage: Double
        let dailyAverage: Double
        let singleDayHigh: Int
        let singleMonthHigh: Int
    }

    struct Statistics: Equatable, Sendable {
        let todayCount: Int
        let todayComparison: PeriodComparison?
        let todayPeakHour: PeakHour?
        let trailingSevenDayCounts: [DayCount]
        /// Average served count per day over the trailing seven days.
        let dailyAverage: Double
        let week: WeekStats
        let month: MonthStats
        let year: YearStats
        /// Sum of every day's max queue number across the whole history.
        let lifetimeTotal: Int
    }

    /// Leading digits of the action title; non-numeric prefixes yield nil.
    static func queueNumber(fromTitle title: String) -> Int? {
        var digits = ""
        for character in title {
            if character.isWholeNumber {
                digits.append(character)
            } else {
                break
            }
        }
        return digits.isEmpty ? nil : Int(digits)
    }

    /// Precomputed view of the completed records of one board. Every metric
    /// below reads from these dictionaries instead of rescanning the raw
    /// records, so one full pass feeds all periods at once.
    struct Aggregation: Sendable {
        /// Max queue number served on each day, keyed by day start.
        let dailyMax: [Date: Int]
        /// Distinct served numbers per day start and hour of day.
        let hourlyNumbers: [Date: [Int: Set<Int>]]
        /// Chronological (timestamp, number) pairs per day start, used for
        /// same-time-of-day comparisons.
        let dayEvents: [Date: [(timestamp: Date, number: Int)]]
        /// Sum of every day's max queue number across the whole history.
        let lifetimeTotal: Int
    }

    static func aggregate(boardID: UUID, records: [CallRecord], calendar: Calendar) -> Aggregation {
        var dailyMax: [Date: Int] = [:]
        var hourlyNumbers: [Date: [Int: Set<Int>]] = [:]
        var dayEvents: [Date: [(timestamp: Date, number: Int)]] = [:]
        for record in records
        where record.boardID == boardID && record.result == .completed {
            guard let number = queueNumber(fromTitle: record.actionTitleSnapshot) else {
                continue
            }
            let dayStart = calendar.startOfDay(for: record.startedAt)
            dailyMax[dayStart] = max(dailyMax[dayStart] ?? 0, number)
            let hour = calendar.component(.hour, from: record.startedAt)
            hourlyNumbers[dayStart, default: [:]][hour, default: []].insert(number)
            dayEvents[dayStart, default: []].append((record.startedAt, number))
        }
        return Aggregation(
            dailyMax: dailyMax,
            hourlyNumbers: hourlyNumbers,
            dayEvents: dayEvents,
            lifetimeTotal: dailyMax.values.reduce(0, +)
        )
    }

    static func statistics(
        boardID: UUID,
        records: [CallRecord],
        calendar: Calendar,
        now: Date
    ) -> Statistics {
        let aggregate = aggregate(boardID: boardID, records: records, calendar: calendar)
        let todayStart = calendar.startOfDay(for: now)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        let trailingSevenDayCounts = trailingSevenDays(aggregate: aggregate, calendar: calendar, now: now)
        return Statistics(
            todayCount: aggregate.dailyMax[todayStart] ?? 0,
            todayComparison: comparisonWithYesterdaySameTime(aggregate: aggregate, calendar: calendar, now: now),
            todayPeakHour: peakHourInWindow(aggregate: aggregate, from: todayStart, to: nextDay, calendar: calendar),
            trailingSevenDayCounts: trailingSevenDayCounts,
            dailyAverage: roundedAverage(
                total: trailingSevenDayCounts.reduce(0) { $0 + $1.count },
                over: Double(trailingSevenDayCounts.count)
            ),
            week: weekStats(aggregate: aggregate, calendar: calendar, now: now),
            month: monthStats(aggregate: aggregate, calendar: calendar, now: now),
            year: yearStats(aggregate: aggregate, calendar: calendar, now: now),
            lifetimeTotal: aggregate.lifetimeTotal
        )
    }

    /// Number served on one calendar day = the max queue number reached.
    static func dailyCount(
        boardID: UUID,
        records: [CallRecord],
        day: Date,
        calendar: Calendar
    ) -> Int {
        let aggregate = aggregate(boardID: boardID, records: records, calendar: calendar)
        return aggregate.dailyMax[calendar.startOfDay(for: day)] ?? 0
    }

    /// Number served on one calendar day up to `upTo` = the max queue
    /// number reached by that moment, used for same-time-of-day compares.
    static func dailyCountUpTo(
        boardID: UUID,
        records: [CallRecord],
        day: Date,
        upTo: Date,
        calendar: Calendar
    ) -> Int {
        let aggregate = aggregate(boardID: boardID, records: records, calendar: calendar)
        return dailyCountUpTo(aggregate: aggregate, day: day, upTo: upTo, calendar: calendar)
    }

    static func weekStats(
        boardID: UUID,
        records: [CallRecord],
        calendar: Calendar,
        now: Date
    ) -> WeekStats {
        weekStats(
            aggregate: aggregate(boardID: boardID, records: records, calendar: calendar),
            calendar: calendar,
            now: now
        )
    }

    static func monthStats(
        boardID: UUID,
        records: [CallRecord],
        calendar: Calendar,
        now: Date
    ) -> MonthStats {
        monthStats(
            aggregate: aggregate(boardID: boardID, records: records, calendar: calendar),
            calendar: calendar,
            now: now
        )
    }

    /// Eight weeks ending with the current week, oldest first.
    static func trailingWeeks(
        boardID: UUID,
        records: [CallRecord],
        calendar: Calendar,
        now: Date
    ) -> [WeekCount] {
        trailingWeeks(
            aggregate: aggregate(boardID: boardID, records: records, calendar: calendar),
            calendar: calendar,
            now: now
        )
    }

    /// Twelve months ending with the current month, oldest first.
    static func trailingMonths(
        boardID: UUID,
        records: [CallRecord],
        calendar: Calendar,
        now: Date
    ) -> [MonthCount] {
        trailingMonths(
            aggregate: aggregate(boardID: boardID, records: records, calendar: calendar),
            calendar: calendar,
            now: now
        )
    }

    static func yearStats(
        boardID: UUID,
        records: [CallRecord],
        calendar: Calendar,
        now: Date
    ) -> YearStats {
        yearStats(
            aggregate: aggregate(boardID: boardID, records: records, calendar: calendar),
            calendar: calendar,
            now: now
        )
    }

    /// The hour window that served the most distinct queue numbers inside
    /// `[from, to)`. A number called twice in the window counts once, so the
    /// metric stays in the same caliber as the period totals. Ties resolve
    /// to the earliest hour so the result is stable.
    static func peakHour(
        boardID: UUID,
        records: [CallRecord],
        from: Date,
        to: Date,
        calendar: Calendar
    ) -> PeakHour? {
        peakHourInWindow(
            aggregate: aggregate(boardID: boardID, records: records, calendar: calendar),
            from: from,
            to: to,
            calendar: calendar
        )
    }

    /// Lifetime served count, same caliber as the period totals: the sum
    /// of every day's max queue number across the whole history.
    static func lifetimeTotal(boardID: UUID, records: [CallRecord], calendar: Calendar) -> Int {
        aggregate(boardID: boardID, records: records, calendar: calendar).lifetimeTotal
    }

    static func comparisonWithLastWeekSameTime(
        boardID: UUID,
        records: [CallRecord],
        calendar: Calendar,
        now: Date
    ) -> PeriodComparison? {
        comparisonWithLastWeekSameTime(
            aggregate: aggregate(boardID: boardID, records: records, calendar: calendar),
            calendar: calendar,
            now: now
        )
    }

    static func comparisonOfLastTwoMonths(
        boardID: UUID,
        records: [CallRecord],
        calendar: Calendar,
        now: Date
    ) -> PeriodComparison? {
        comparisonOfLastTwoMonths(
            aggregate: aggregate(boardID: boardID, records: records, calendar: calendar),
            calendar: calendar,
            now: now
        )
    }

    static func comparisonWithYesterdaySameTime(
        boardID: UUID,
        records: [CallRecord],
        calendar: Calendar,
        now: Date
    ) -> PeriodComparison? {
        comparisonWithYesterdaySameTime(
            aggregate: aggregate(boardID: boardID, records: records, calendar: calendar),
            calendar: calendar,
            now: now
        )
    }

    /// Seven days ending today (including today), oldest first.
    static func trailingSevenDays(
        boardID: UUID,
        records: [CallRecord],
        calendar: Calendar,
        now: Date
    ) -> [DayCount] {
        trailingSevenDays(
            aggregate: aggregate(boardID: boardID, records: records, calendar: calendar),
            calendar: calendar,
            now: now
        )
    }

    // MARK: - Aggregate-based metrics

    private static func weekStats(aggregate: Aggregation, calendar: Calendar, now: Date) -> WeekStats {
        let weekStart = startOfCurrentWeek(calendar: calendar, now: now)
        let dailyCounts = (0..<7).compactMap { offset -> DayCount? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else {
                return nil
            }
            return DayCount(day: day, count: aggregate.dailyMax[day] ?? 0)
        }
        let weeklyCount = dailyCounts.reduce(0) { $0 + $1.count }
        let comparison = comparisonWithLastWeekSameTime(aggregate: aggregate, calendar: calendar, now: now)
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            return WeekStats(
                weeklyCount: weeklyCount, dailyCounts: dailyCounts, weeklyCounts: [],
                comparison: comparison,
                peakHour: nil, weeklyAverage: 0, singleDayHigh: 0
            )
        }
        let peak = peakHourInWindow(aggregate: aggregate, from: weekStart, to: weekEnd, calendar: calendar)
        let elapsedDays = elapsedDayCount(from: weekStart, calendar: calendar, now: now)
        let trailing = trailingWeeks(aggregate: aggregate, calendar: calendar, now: now)
        // Seven completed weeks plus the current week's elapsed share, so a
        // mid-week average is not diluted by days that have not happened yet.
        let elapsedWeeks = 7 + Double(elapsedDays) / 7
        return WeekStats(
            weeklyCount: weeklyCount,
            dailyCounts: dailyCounts,
            weeklyCounts: trailing,
            comparison: comparison,
            peakHour: peak,
            weeklyAverage: roundedAverage(total: trailing.reduce(0) { $0 + $1.count }, over: elapsedWeeks),
            singleDayHigh: dailyCounts.map(\.count).max() ?? 0
        )
    }

    private static func monthStats(aggregate: Aggregation, calendar: Calendar, now: Date) -> MonthStats {
        let monthRange = calendar.dateInterval(of: .month, for: now)
        guard let monthRange else {
            return MonthStats(
                monthlyCount: 0, dailyCounts: [], monthlyCounts: [], comparison: nil,
                peakHour: nil, monthlyAverage: 0, singleDayHigh: 0
            )
        }
        var dailyCounts: [DayCount] = []
        var cursor = monthRange.start
        while cursor < monthRange.end {
            dailyCounts.append(DayCount(day: cursor, count: aggregate.dailyMax[cursor] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        let monthlyCount = dailyCounts.reduce(0) { $0 + $1.count }
        let comparison = comparisonOfLastTwoMonths(aggregate: aggregate, calendar: calendar, now: now)
        let peak = peakHourInWindow(aggregate: aggregate, from: monthRange.start, to: monthRange.end, calendar: calendar)
        let trailing = trailingMonths(aggregate: aggregate, calendar: calendar, now: now)
        // Eleven completed months plus the current month's elapsed share.
        let elapsedDays = elapsedDayCount(from: monthRange.start, calendar: calendar, now: now)
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthRange.start)?.count ?? 30
        let elapsedMonths = 11 + Double(elapsedDays) / Double(daysInMonth)
        return MonthStats(
            monthlyCount: monthlyCount,
            dailyCounts: dailyCounts,
            monthlyCounts: trailing,
            comparison: comparison,
            peakHour: peak,
            monthlyAverage: roundedAverage(total: trailing.reduce(0) { $0 + $1.count }, over: elapsedMonths),
            singleDayHigh: dailyCounts.map(\.count).max() ?? 0
        )
    }

    private static func trailingWeeks(aggregate: Aggregation, calendar: Calendar, now: Date) -> [WeekCount] {
        let thisWeekStart = startOfCurrentWeek(calendar: calendar, now: now)
        return (0..<8).compactMap { offset -> WeekCount? in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: offset - 7, to: thisWeekStart) else {
                return nil
            }
            return WeekCount(weekStart: weekStart, count: dailySum(aggregate: aggregate, from: weekStart, days: 7, calendar: calendar))
        }
    }

    private static func trailingMonths(aggregate: Aggregation, calendar: Calendar, now: Date) -> [MonthCount] {
        guard let thisMonth = calendar.dateInterval(of: .month, for: now) else {
            return []
        }
        return (0..<12).compactMap { offset -> MonthCount? in
            guard let monthStart = calendar.date(byAdding: .month, value: offset - 11, to: thisMonth.start) else {
                return nil
            }
            return MonthCount(monthStart: monthStart, count: monthTotal(aggregate: aggregate, start: monthStart, calendar: calendar))
        }
    }

    private static func yearStats(aggregate: Aggregation, calendar: Calendar, now: Date) -> YearStats {
        guard let yearRange = calendar.dateInterval(of: .year, for: now) else {
            return YearStats(
                yearlyCount: 0, monthlyCounts: [], peakHour: nil,
                monthlyAverage: 0, dailyAverage: 0, singleDayHigh: 0, singleMonthHigh: 0
            )
        }
        let todayStart = calendar.startOfDay(for: now)
        // Months from January through the current month only; future months
        // have no data yet and would just pad the chart with zeros.
        var monthlyCounts: [MonthCount] = []
        var cursor = yearRange.start
        while cursor <= now {
            monthlyCounts.append(
                MonthCount(monthStart: cursor, count: monthTotal(aggregate: aggregate, start: cursor, calendar: calendar))
            )
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        // Walk every elapsed day of the year once to derive the total,
        // the daily average and the single-day high in the same caliber.
        var yearlyCount = 0
        var singleDayHigh = 0
        var elapsedDays = 0
        var day = yearRange.start
        while day <= todayStart {
            let count = aggregate.dailyMax[day] ?? 0
            yearlyCount += count
            singleDayHigh = max(singleDayHigh, count)
            elapsedDays += 1
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        let peak = peakHourInWindow(aggregate: aggregate, from: yearRange.start, to: yearRange.end, calendar: calendar)
        return YearStats(
            yearlyCount: yearlyCount,
            monthlyCounts: monthlyCounts,
            peakHour: peak,
            monthlyAverage: average(total: yearlyCount, elapsedDays: max(monthlyCounts.count, 1)),
            dailyAverage: average(total: yearlyCount, elapsedDays: max(elapsedDays, 1)),
            singleDayHigh: singleDayHigh,
            singleMonthHigh: monthlyCounts.map(\.count).max() ?? 0
        )
    }

    /// Peak hour of `[from, to)` by merging each covered day's hourly sets,
    /// so a number repeated on different days of the window counts once.
    private static func peakHourInWindow(
        aggregate: Aggregation,
        from: Date,
        to: Date,
        calendar: Calendar
    ) -> PeakHour? {
        var merged: [Int: Set<Int>] = [:]
        var cursor = calendar.startOfDay(for: from)
        while cursor < to {
            if let hours = aggregate.hourlyNumbers[cursor] {
                for (hour, numbers) in hours {
                    merged[hour, default: []].formUnion(numbers)
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        guard let best = merged.max(by: {
            $0.value.count != $1.value.count ? $0.value.count < $1.value.count : $0.key > $1.key
        }) else {
            return nil
        }
        return PeakHour(hour: best.key, servedCount: best.value.count)
    }

    private static func dailySum(aggregate: Aggregation, from start: Date, days: Int, calendar: Calendar) -> Int {
        var sum = 0
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            sum += aggregate.dailyMax[day] ?? 0
        }
        return sum
    }

    private static func monthTotal(aggregate: Aggregation, start: Date, calendar: Calendar) -> Int {
        guard let range = calendar.dateInterval(of: .month, for: start) else {
            return 0
        }
        var sum = 0
        var cursor = range.start
        while cursor < range.end {
            sum += aggregate.dailyMax[cursor] ?? 0
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return sum
    }

    private static func trailingSevenDays(aggregate: Aggregation, calendar: Calendar, now: Date) -> [DayCount] {
        let todayStart = calendar.startOfDay(for: now)
        return (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset - 6, to: todayStart) ?? todayStart
            return DayCount(day: day, count: aggregate.dailyMax[day] ?? 0)
        }
    }

    private static func dailyCountUpTo(aggregate: Aggregation, day: Date, upTo: Date, calendar: Calendar) -> Int {
        let dayStart = calendar.startOfDay(for: day)
        // Clamp to the day boundary so a cutoff derived via raw time
        // intervals can never leak into the following day, which matters
        // around DST transitions where day lengths differ.
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let cutoff = min(upTo, dayEnd)
        let events = aggregate.dayEvents[dayStart] ?? []
        var maximum = 0
        for event in events where event.timestamp <= cutoff {
            maximum = max(maximum, event.number)
        }
        return maximum
    }

    // MARK: - Comparisons (same-period against the previous period)

    private static func comparisonWithLastWeekSameTime(
        aggregate: Aggregation,
        calendar: Calendar,
        now: Date
    ) -> PeriodComparison? {
        let thisWeekStart = startOfCurrentWeek(calendar: calendar, now: now)
        guard let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) else {
            return nil
        }
        // A partial week only makes sense against last week up to the same
        // weekday and time of day: full days before it, same time on the
        // matching weekday, and nothing after it.
        let todayStart = calendar.startOfDay(for: now)
        let daysSinceWeekStart = calendar.dateComponents([.day], from: thisWeekStart, to: todayStart).day ?? 0
        let elapsedToday = now.timeIntervalSince(todayStart)
        let recent = dailySum(aggregate: aggregate, from: thisWeekStart, days: 7, calendar: calendar)
        var earlier = 0
        for offset in 0...min(daysSinceWeekStart, 6) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: lastWeekStart) else {
                continue
            }
            earlier += dailyCountUpTo(
                aggregate: aggregate, day: day, upTo: day.addingTimeInterval(elapsedToday), calendar: calendar
            )
        }
        return makeComparison(recent: recent, earlier: earlier)
    }

    private static func comparisonOfLastTwoMonths(
        aggregate: Aggregation,
        calendar: Calendar,
        now: Date
    ) -> PeriodComparison? {
        guard let thisMonth = calendar.dateInterval(of: .month, for: now),
              let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonth.start),
              let twoMonthsAgoStart = calendar.date(byAdding: .month, value: -2, to: thisMonth.start) else {
            return nil
        }
        let lastMonth = monthTotal(aggregate: aggregate, start: lastMonthStart, calendar: calendar)
        let earlierMonth = monthTotal(aggregate: aggregate, start: twoMonthsAgoStart, calendar: calendar)
        return makeComparison(recent: lastMonth, earlier: earlierMonth)
    }

    private static func comparisonWithYesterdaySameTime(
        aggregate: Aggregation,
        calendar: Calendar,
        now: Date
    ) -> PeriodComparison? {
        let todayStart = calendar.startOfDay(for: now)
        guard let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) else {
            return nil
        }
        // A partial today only makes sense against yesterday up to the same
        // time of day; comparing against a full day would always look bad.
        let elapsed = now.timeIntervalSince(todayStart)
        let yesterdayCutoff = yesterdayStart.addingTimeInterval(elapsed)
        let recent = dailyCountUpTo(aggregate: aggregate, day: todayStart, upTo: now, calendar: calendar)
        let earlier = dailyCountUpTo(
            aggregate: aggregate, day: yesterdayStart, upTo: yesterdayCutoff, calendar: calendar
        )
        return makeComparison(recent: recent, earlier: earlier)
    }

    // MARK: - Helpers

    /// Whole days elapsed inside the current period, at least one, so a
    /// mid-week average is not diluted by days that have not happened yet.
    private static func elapsedDayCount(from periodStart: Date, calendar: Calendar, now: Date) -> Int {
        let elapsed = calendar.dateComponents([.day], from: periodStart, to: calendar.startOfDay(for: now)).day ?? 0
        return max(elapsed + 1, 1)
    }

    private static func average(total: Int, elapsedDays: Int) -> Double {
        (Double(total) / Double(elapsedDays) * 10).rounded() / 10
    }

    /// One-decimal average over a fractional period count, e.g. 7.4 weeks.
    private static func roundedAverage(total: Int, over periods: Double) -> Double {
        guard periods > 0 else {
            return 0
        }
        return (Double(total) / periods * 10).rounded() / 10
    }

    private static func makeComparison(recent: Int, earlier: Int) -> PeriodComparison? {
        let percentage: Int?
        if earlier > 0 {
            percentage = Int((Double(recent - earlier) / Double(earlier) * 100).rounded())
        } else {
            percentage = nil
        }
        return PeriodComparison(recent: recent, earlier: earlier, percentage: percentage)
    }

    /// Monday 00:00 of the week containing `now` (natural week starts Monday).
    static func startOfCurrentWeek(calendar: Calendar, now: Date) -> Date {
        let startOfDay = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: startOfDay)
        // Gregorian: Sunday == 1 ... Saturday == 7. Shift so Monday == 0.
        var daysSinceMonday = weekday - 2
        if daysSinceMonday < 0 {
            daysSinceMonday += 7
        }
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: startOfDay) ?? startOfDay
    }
}
