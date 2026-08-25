import Foundation
import Testing
@testable import CallDesk

@Suite("Board statistics service")
struct BoardStatisticsServiceTests {
    private let boardID = UUID()
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2 // Monday
        return calendar
    }

    private func record(title: String, boardID: UUID, day: Date, result: CallResult = .completed) throws -> CallRecord {
        try CallRecord(
            actionID: UUID(),
            boardID: boardID,
            actionTitleSnapshot: title,
            spokenTextSnapshot: title,
            startedAt: day,
            completedAt: day.addingTimeInterval(5),
            result: result
        )
    }

    private func day(_ year: Int, _ month: Int, _ dayNumber: Int, hour: Int = 10) -> Date {
        let components = DateComponents(calendar: calendar, year: year, month: month, day: dayNumber, hour: hour)
        return calendar.date(from: components)!
    }

    @Test("Daily count is the max queue number reached, filling skipped numbers")
    func dailyCountIsMaxNumber() throws {
        // Monday 2026-07-06: called 3, 5, 8 → max 8; gaps 4,6,7 implied.
        let monday = day(2026, 7, 6)
        let records = [
            try record(title: "3", boardID: boardID, day: monday),
            try record(title: "5", boardID: boardID, day: monday),
            try record(title: "8", boardID: boardID, day: monday)
        ]
        #expect(BoardStatisticsService.dailyCount(boardID: boardID, records: records, day: monday, calendar: calendar) == 8)
    }

    @Test("Non-numeric titles and other boards are excluded")
    func excludesNonNumericAndOtherBoards() throws {
        let monday = day(2026, 7, 6)
        let otherBoard = UUID()
        let records = [
            try record(title: "VIP", boardID: boardID, day: monday),
            try record(title: "8", boardID: otherBoard, day: monday),
            try record(title: "10", boardID: boardID, day: monday)
        ]
        #expect(BoardStatisticsService.dailyCount(boardID: boardID, records: records, day: monday, calendar: calendar) == 10)
    }

    @Test("Day with only non-completed records counts as zero")
    func nonCompletedRecordsDontCount() throws {
        let monday = day(2026, 7, 6)
        let records = [try record(title: "8", boardID: boardID, day: monday, result: .cancelled)]
        #expect(BoardStatisticsService.dailyCount(boardID: boardID, records: records, day: monday, calendar: calendar) == 0)
    }

    @Test("Queue number parses leading digits only")
    func queueNumberParsesLeadingDigits() {
        #expect(BoardStatisticsService.queueNumber(fromTitle: "7") == 7)
        #expect(BoardStatisticsService.queueNumber(fromTitle: "42") == 42)
        #expect(BoardStatisticsService.queueNumber(fromTitle: "A021") == nil)
        #expect(BoardStatisticsService.queueNumber(fromTitle: "暂停办理") == nil)
        #expect(BoardStatisticsService.queueNumber(fromTitle: "") == nil)
    }

    @Test("Week stats sum the daily maxima of the current natural week")
    func weekStatsSumCurrentWeek() throws {
        let monday = day(2026, 7, 6)
        let tuesday = day(2026, 7, 7)
        let records = [
            try record(title: "3", boardID: boardID, day: monday),
            try record(title: "5", boardID: boardID, day: tuesday)
        ]
        let stats = BoardStatisticsService.weekStats(boardID: boardID, records: records, calendar: calendar, now: tuesday)
        #expect(stats.weeklyCount == 8)
        #expect(stats.dailyCounts.count == 7)
        #expect(stats.dailyCounts.first?.day == calendar.startOfDay(for: monday))
    }

    @Test("Week comparison matches this week against last week up to the same time")
    func weekComparisonComparesSameWeekTime() throws {
        // now = Wednesday 2026-07-08 18:00. This week starts 7/6; last week
        // runs 6/29-7/5. Last week's Wednesday-evening number (7/1 20:00)
        // must not count, otherwise a partial week always looks worse.
        let now = day(2026, 7, 8, hour: 18)
        let records = [
            try record(title: "6", boardID: boardID, day: day(2026, 7, 6)),
            try record(title: "9", boardID: boardID, day: day(2026, 7, 8, hour: 10)),
            try record(title: "10", boardID: boardID, day: day(2026, 6, 29)),
            try record(title: "4", boardID: boardID, day: day(2026, 6, 30)),
            try record(title: "30", boardID: boardID, day: day(2026, 7, 1, hour: 20))
        ]
        let comparison = BoardStatisticsService.comparisonWithLastWeekSameTime(
            boardID: boardID, records: records, calendar: calendar, now: now
        )
        #expect(comparison?.recent == 15)
        #expect(comparison?.earlier == 14)
        #expect(comparison?.percentage == 7)
    }

    @Test("Month stats sum the daily maxima of the current month")
    func monthStatsSumCurrentMonth() throws {
        let now = day(2026, 7, 15)
        let records = [
            try record(title: "2", boardID: boardID, day: day(2026, 7, 1)),
            try record(title: "3", boardID: boardID, day: day(2026, 7, 15))
        ]
        let stats = BoardStatisticsService.monthStats(boardID: boardID, records: records, calendar: calendar, now: now)
        #expect(stats.monthlyCount == 5)
        #expect(stats.dailyCounts.count == 31)
    }

    @Test("Month comparison uses last month vs the one before it")
    func monthComparisonUsesTwoCompletedMonths() throws {
        let now = day(2026, 8, 1)
        let records = [
            try record(title: "20", boardID: boardID, day: day(2026, 7, 10)),
            try record(title: "10", boardID: boardID, day: day(2026, 6, 10))
        ]
        let comparison = BoardStatisticsService.comparisonOfLastTwoMonths(
            boardID: boardID, records: records, calendar: calendar, now: now
        )
        #expect(comparison?.recent == 20)
        #expect(comparison?.earlier == 10)
        #expect(comparison?.percentage == 100)
    }

    @Test("Comparison percentage is nil when the earlier total is zero")
    func comparisonPercentageNilWhenEarlierIsZero() throws {
        let records = [try record(title: "10", boardID: boardID, day: day(2026, 7, 13, hour: 9))]
        let comparison = BoardStatisticsService.comparisonWithLastWeekSameTime(
            boardID: boardID, records: records, calendar: calendar, now: day(2026, 7, 13, hour: 10)
        )
        #expect(comparison?.recent == 10)
        #expect(comparison?.earlier == 0)
        #expect(comparison?.percentage == nil)
    }

    @Test("Today count is exposed top-level")
    func statisticsExposeTodayCount() throws {
        let now = day(2026, 7, 6, hour: 18)
        let records = [try record(title: "6", boardID: boardID, day: now)]
        let stats = BoardStatisticsService.statistics(boardID: boardID, records: records, calendar: calendar, now: now)
        #expect(stats.todayCount == 6)
        #expect(stats.week.weeklyCount == 6)
    }

    @Test("Day comparison matches today against yesterday up to the same time")
    func statisticsCompareYesterdaySameTime() throws {
        // now = 2026-07-08 18:00. Yesterday's late-evening number (20:00)
        // must not count, otherwise a partial today always looks worse.
        let now = day(2026, 7, 8, hour: 18)
        let records = [
            try record(title: "8", boardID: boardID, day: day(2026, 7, 8, hour: 10)),
            try record(title: "6", boardID: boardID, day: day(2026, 7, 7, hour: 9)),
            try record(title: "20", boardID: boardID, day: day(2026, 7, 7, hour: 20))
        ]
        let stats = BoardStatisticsService.statistics(boardID: boardID, records: records, calendar: calendar, now: now)
        #expect(stats.todayComparison?.recent == 8)
        #expect(stats.todayComparison?.earlier == 6)
        #expect(stats.todayComparison?.percentage == 33)
    }

    @Test("Trailing seven days end today, oldest first, and include today")
    func statisticsExposeTrailingSevenDays() throws {
        let now = day(2026, 7, 8, hour: 18)
        let records = [
            try record(title: "3", boardID: boardID, day: day(2026, 7, 8)),
            try record(title: "2", boardID: boardID, day: day(2026, 7, 6))
        ]
        let stats = BoardStatisticsService.statistics(boardID: boardID, records: records, calendar: calendar, now: now)
        #expect(stats.trailingSevenDayCounts.count == 7)
        #expect(stats.trailingSevenDayCounts.first?.day == calendar.startOfDay(for: day(2026, 7, 2)))
        #expect(stats.trailingSevenDayCounts.last?.day == calendar.startOfDay(for: day(2026, 7, 8)))
        #expect(stats.trailingSevenDayCounts.map(\.count) == [0, 0, 0, 0, 2, 0, 3])
    }

    @Test("Peak hour counts distinct served numbers, not call events")
    func peakHourPicksBusiestHour() throws {
        let records = [
            try record(title: "1", boardID: boardID, day: day(2026, 7, 6, hour: 11)),
            try record(title: "2", boardID: boardID, day: day(2026, 7, 6, hour: 11)),
            try record(title: "3", boardID: boardID, day: day(2026, 7, 6, hour: 18)),
            try record(title: "4", boardID: boardID, day: day(2026, 7, 6, hour: 11), result: .cancelled)
        ]
        let peak = BoardStatisticsService.peakHour(
            boardID: boardID,
            records: records,
            from: calendar.startOfDay(for: day(2026, 7, 6)),
            to: calendar.startOfDay(for: day(2026, 7, 7)),
            calendar: calendar
        )
        #expect(peak?.hour == 11)
        #expect(peak?.servedCount == 2)
    }

    @Test("Repeated calls of one number count once in the peak hour")
    func peakHourCountsDistinctNumbersOnce() throws {
        let records = [
            try record(title: "5", boardID: boardID, day: day(2026, 7, 6, hour: 11)),
            try record(title: "5", boardID: boardID, day: day(2026, 7, 6, hour: 11)),
            try record(title: "6", boardID: boardID, day: day(2026, 7, 6, hour: 11)),
            try record(title: "7", boardID: boardID, day: day(2026, 7, 6, hour: 15)),
            try record(title: "VIP", boardID: boardID, day: day(2026, 7, 6, hour: 15)),
            try record(title: "VIP", boardID: boardID, day: day(2026, 7, 6, hour: 15))
        ]
        let peak = BoardStatisticsService.peakHour(
            boardID: boardID,
            records: records,
            from: calendar.startOfDay(for: day(2026, 7, 6)),
            to: calendar.startOfDay(for: day(2026, 7, 7)),
            calendar: calendar
        )
        #expect(peak?.hour == 11)
        #expect(peak?.servedCount == 2)
    }

    @Test("Peak hour is nil when the window has no completed calls")
    func peakHourNilWithoutCompletedCalls() throws {
        let records = [try record(title: "1", boardID: boardID, day: day(2026, 7, 6), result: .cancelled)]
        let peak = BoardStatisticsService.peakHour(
            boardID: boardID,
            records: records,
            from: calendar.startOfDay(for: day(2026, 7, 6)),
            to: calendar.startOfDay(for: day(2026, 7, 7)),
            calendar: calendar
        )
        #expect(peak == nil)
    }

    @Test("Weekly average spreads the trailing weeks over elapsed week share")
    func weeklyAverageUsesElapsedWeeks() throws {
        // Sunday 2026-07-12: seven completed weeks plus a full current week
        // = exactly 8 week units, so 40 served / 8 = 5 per week.
        let now = day(2026, 7, 12)
        let records = [
            try record(title: "10", boardID: boardID, day: day(2026, 7, 6)),
            try record(title: "30", boardID: boardID, day: day(2026, 7, 7))
        ]
        let stats = BoardStatisticsService.weekStats(boardID: boardID, records: records, calendar: calendar, now: now)
        #expect(stats.weeklyAverage == 5)
        #expect(stats.singleDayHigh == 30)
    }

    @Test("Monthly average spreads the trailing months over elapsed month share")
    func monthlyAverageUsesElapsedMonths() throws {
        // 2026-07-31: eleven completed months plus a full current month
        // = exactly 12 month units, so 36 served / 12 = 3 per month.
        let now = day(2026, 7, 31)
        let records = [
            try record(title: "24", boardID: boardID, day: day(2026, 7, 15)),
            try record(title: "12", boardID: boardID, day: day(2026, 6, 10))
        ]
        let stats = BoardStatisticsService.monthStats(boardID: boardID, records: records, calendar: calendar, now: now)
        #expect(stats.monthlyAverage == 3)
    }

    @Test("Daily average covers the trailing seven days ending today")
    func dailyAverageOverTrailingSevenDays() throws {
        let now = day(2026, 7, 8, hour: 18)
        let records = [
            try record(title: "5", boardID: boardID, day: day(2026, 7, 8)),
            try record(title: "2", boardID: boardID, day: day(2026, 7, 6))
        ]
        let stats = BoardStatisticsService.statistics(boardID: boardID, records: records, calendar: calendar, now: now)
        #expect(stats.dailyAverage == 1) // (5 + 2) / 7
    }

    @Test("Lifetime total sums every day's max queue number")
    func lifetimeTotalSumsDailyMaxima() throws {
        let records = [
            try record(title: "3", boardID: boardID, day: day(2026, 7, 6)),
            try record(title: "8", boardID: boardID, day: day(2026, 7, 6)),
            try record(title: "5", boardID: boardID, day: day(2026, 7, 7)),
            try record(title: "VIP", boardID: boardID, day: day(2026, 7, 8))
        ]
        let total = BoardStatisticsService.lifetimeTotal(boardID: boardID, records: records, calendar: calendar)
        #expect(total == 13) // 8 + 5
    }

    @Test("Statistics exposes today's peak hour and lifetime total")
    func statisticsExposePeakHourAndLifetime() throws {
        let now = day(2026, 7, 8, hour: 15)
        let records = [
            try record(title: "4", boardID: boardID, day: now),
            try record(title: "10", boardID: boardID, day: day(2026, 7, 6))
        ]
        let stats = BoardStatisticsService.statistics(boardID: boardID, records: records, calendar: calendar, now: now)
        #expect(stats.todayPeakHour?.hour == 15)
        #expect(stats.todayPeakHour?.servedCount == 1)
        #expect(stats.lifetimeTotal == 14)
    }

    @Test("Trailing weeks cover eight weeks ending with the current one")
    func trailingWeeksEndWithCurrentWeek() throws {
        // Wednesday 2026-07-08; this week started Monday 2026-07-06.
        let now = day(2026, 7, 8)
        let records = [
            try record(title: "9", boardID: boardID, day: day(2026, 7, 6)),
            try record(title: "4", boardID: boardID, day: day(2026, 6, 29))
        ]
        let weeks = BoardStatisticsService.trailingWeeks(
            boardID: boardID, records: records, calendar: calendar, now: now
        )
        #expect(weeks.count == 8)
        #expect(weeks.last?.weekStart == calendar.startOfDay(for: day(2026, 7, 6)))
        #expect(weeks.last?.count == 9)
        #expect(weeks.dropLast().last?.weekStart == calendar.startOfDay(for: day(2026, 6, 29)))
        #expect(weeks.dropLast().last?.count == 4)
    }

    @Test("Trailing months cover twelve months ending with the current one")
    func trailingMonthsEndWithCurrentMonth() throws {
        let now = day(2026, 8, 5)
        let records = [
            try record(title: "20", boardID: boardID, day: day(2026, 7, 10)),
            try record(title: "6", boardID: boardID, day: day(2026, 8, 3))
        ]
        let months = BoardStatisticsService.trailingMonths(
            boardID: boardID, records: records, calendar: calendar, now: now
        )
        #expect(months.count == 12)
        #expect(months.last?.monthStart == day(2026, 8, 1, hour: 0))
        #expect(months.last?.count == 6)
        #expect(months.dropLast().last?.monthStart == day(2026, 7, 1, hour: 0))
        #expect(months.dropLast().last?.count == 20)
    }

    @Test("Week and month stats expose the trailing series")
    func statsExposeTrailingSeries() throws {
        let now = day(2026, 7, 8)
        let records = [try record(title: "6", boardID: boardID, day: day(2026, 7, 6))]
        let week = BoardStatisticsService.weekStats(boardID: boardID, records: records, calendar: calendar, now: now)
        let month = BoardStatisticsService.monthStats(boardID: boardID, records: records, calendar: calendar, now: now)
        #expect(week.weeklyCounts.count == 8)
        #expect(month.monthlyCounts.count == 12)
    }

    @Test("Year stats sum the daily maxima and expose averages and highs")
    func yearStatsSummarizeTheYear() throws {
        // 2026-07-08: elapsed days = 31+28+31+30+31+30+8 = 189, months = 7.
        let now = day(2026, 7, 8)
        let records = [
            try record(title: "30", boardID: boardID, day: day(2026, 3, 10)),
            try record(title: "20", boardID: boardID, day: day(2026, 6, 15)),
            try record(title: "9", boardID: boardID, day: day(2026, 7, 6))
        ]
        let stats = BoardStatisticsService.yearStats(boardID: boardID, records: records, calendar: calendar, now: now)
        #expect(stats.yearlyCount == 59)
        #expect(stats.monthlyCounts.count == 7)
        #expect(stats.monthlyCounts.last?.count == 9)
        #expect(stats.singleDayHigh == 30)
        #expect(stats.singleMonthHigh == 30)
        // 59 / 7 months = 8.4
        #expect(stats.monthlyAverage == 8.4)
        // 59 / 189 elapsed days = 0.3
        #expect(stats.dailyAverage == 0.3)
    }

    @Test("Year stats expose the year-wide peak hour in served count")
    func yearStatsExposePeakHour() throws {
        let now = day(2026, 7, 8)
        let records = [
            try record(title: "1", boardID: boardID, day: day(2026, 2, 3, hour: 12)),
            try record(title: "2", boardID: boardID, day: day(2026, 5, 20, hour: 12)),
            try record(title: "3", boardID: boardID, day: day(2026, 7, 1, hour: 9))
        ]
        let stats = BoardStatisticsService.yearStats(boardID: boardID, records: records, calendar: calendar, now: now)
        #expect(stats.peakHour?.hour == 12)
        #expect(stats.peakHour?.servedCount == 2)
    }

    @Test("Trailing series cross the year boundary into the previous year")
    func trailingSeriesCrossYearBoundary() throws {
        // Friday 2026-01-02: this week started Monday 2025-12-29, so the
        // eight-week window must reach into December of the previous year.
        let now = day(2026, 1, 2)
        let records = [
            try record(title: "7", boardID: boardID, day: day(2025, 12, 30)),
            try record(title: "12", boardID: boardID, day: day(2025, 12, 10))
        ]
        let weeks = BoardStatisticsService.trailingWeeks(
            boardID: boardID, records: records, calendar: calendar, now: now
        )
        #expect(weeks.count == 8)
        #expect(weeks.first?.weekStart == calendar.startOfDay(for: day(2025, 11, 10)))
        #expect(weeks.last?.weekStart == calendar.startOfDay(for: day(2025, 12, 29)))
        #expect(weeks.last?.count == 7)

        let months = BoardStatisticsService.trailingMonths(
            boardID: boardID, records: records, calendar: calendar, now: now
        )
        #expect(months.count == 12)
        #expect(months.first?.monthStart == day(2025, 2, 1, hour: 0))
        #expect(months.last?.monthStart == day(2026, 1, 1, hour: 0))
        // December 2025 holds both records: 7 + 12.
        #expect(months.dropLast().last?.count == 19)
    }

    @Test("Leap-year February keeps the monthly average honest")
    func leapYearFebruaryAverage() throws {
        // 2028 is a leap year: February has 29 days, so on 2/29 the month
        // counts as exactly 12 elapsed month units over the trailing window.
        let now = day(2028, 2, 29)
        let records = [try record(title: "24", boardID: boardID, day: day(2028, 2, 15))]
        let stats = BoardStatisticsService.monthStats(boardID: boardID, records: records, calendar: calendar, now: now)
        #expect(stats.monthlyCount == 24)
        #expect(stats.dailyCounts.count == 29)
        #expect(stats.monthlyAverage == 2) // 24 / 12 month units

        let year = BoardStatisticsService.yearStats(boardID: boardID, records: records, calendar: calendar, now: now)
        // 31 (Jan) + 29 (Feb) = 60 elapsed days.
        #expect(year.dailyAverage == 0.4) // 24 / 60
    }

    @Test("Averages stay well defined exactly at period starts")
    func periodStartBoundaries() throws {
        // Monday 2026-07-06 00:00 is exactly the week start and the sixth
        // day of the month: elapsed shares must clamp to at least one unit.
        let mondayStart = calendar.startOfDay(for: day(2026, 7, 6))
        let records = [try record(title: "4", boardID: boardID, day: day(2026, 7, 1))]
        let week = BoardStatisticsService.weekStats(
            boardID: boardID, records: records, calendar: calendar, now: mondayStart
        )
        // Trailing eight-week total is 4 over exactly 7 + 1/7 week units.
        #expect(week.weeklyAverage == 0.6)

        let month = BoardStatisticsService.monthStats(
            boardID: boardID, records: records, calendar: calendar, now: mondayStart
        )
        // 4 served over 11 + 6/31 month units ≈ 0.4.
        #expect(month.monthlyAverage == 0.4)

        // Exactly at a month start the previous-period base can be zero,
        // so the percentage stays nil instead of dividing by zero.
        let monthStart = day(2026, 8, 1, hour: 0)
        let comparison = BoardStatisticsService.comparisonOfLastTwoMonths(
            boardID: boardID, records: records, calendar: calendar, now: monthStart
        )
        #expect(comparison?.recent == 4)
        #expect(comparison?.percentage == nil)
    }
}
