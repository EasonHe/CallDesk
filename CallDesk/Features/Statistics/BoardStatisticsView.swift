import Charts
import SwiftUI

struct BoardStatisticsView: View {
    @StateObject private var viewModel: BoardStatisticsViewModel
    /// Bumped by the app root whenever the operator returns to this page
    /// (tab tap or pager swipe) so the numbers reflect calls made while the
    /// page was off screen.
    private let refreshToken: Int

    init(boardID: UUID, dependencies: AppDependencies, refreshToken: Int = 0) {
        _viewModel = StateObject(wrappedValue: BoardStatisticsViewModel(boardID: boardID, dependencies: dependencies))
        self.refreshToken = refreshToken
    }

    var body: some View {
        content
            .task {
                await viewModel.load()
            }
            .onChange(of: refreshToken) { _ in
                Task {
                    await viewModel.reload()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            FeatureEmptyStateView(
                systemImage: "chart.line.uptrend.xyaxis",
                title: "暂无统计",
                message: "该面板还没有呼叫记录。"
            )
        case .loaded(let statistics):
            loadedView(statistics)
        case .failed:
            FeatureErrorStateView {
                Task {
                    await viewModel.load()
                }
            }
        }
    }

    private func loadedView(_ statistics: BoardStatisticsService.Statistics) -> some View {
        List {
            Picker("周期", selection: $viewModel.selectedPeriod) {
                ForEach(BoardStatisticsViewModel.Period.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .pickerStyle(.segmented)

            switch viewModel.selectedPeriod {
            case .day:
                daySection(statistics)
            case .week:
                weekSection(statistics)
            case .month:
                monthSection(statistics)
            case .year:
                yearSection(statistics)
            }
        }
        // The pager is a UIKit collection view that does not propagate the
        // root safe-area inset, so the last section would scroll underneath
        // the bottom menu. Reserving bottom space keeps the final chart
        // fully visible above the menu bar.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: 60)
                .accessibilityHidden(true)
        }
        .refreshable {
            await viewModel.reload()
        }
    }

    private func daySection(_ statistics: BoardStatisticsService.Statistics) -> some View {
        Group {
            Section {
                heroCard(count: statistics.todayCount, title: "今日单数", caption: "历史累计 \(statistics.lifetimeTotal) 单")
                comparisonRow("昨日同时段对比", statistics.todayComparison)
                metricRow(
                    icon: "clock.fill",
                    title: "今日高峰时段",
                    value: peakHourLabel(statistics.todayPeakHour)
                )
                metricRow(icon: "chart.bar.fill", title: "日均单数（近 7 日平均）", value: averageLabel(statistics.dailyAverage))
            }
            Section("最近 7 日走势") {
                areaChart(statistics.trailingSevenDayCounts, highlightedDay: Date())
                    .frame(height: 180)
            }
        }
    }

    private func weekSection(_ statistics: BoardStatisticsService.Statistics) -> some View {
        Group {
            Section {
                heroCard(count: statistics.week.weeklyCount, title: "本周单数", caption: "历史累计 \(statistics.lifetimeTotal) 单")
                comparisonRow("上周同时段对比", statistics.week.comparison)
                metricRow(
                    icon: "clock.fill",
                    title: "本周高峰时段",
                    value: peakHourLabel(statistics.week.peakHour)
                )
                metricRow(icon: "chart.bar.fill", title: "周均单数（近 8 周平均）", value: averageLabel(statistics.week.weeklyAverage))
                metricRow(icon: "trophy.fill", title: "单日最高", value: "\(statistics.week.singleDayHigh)")
            }
            Section("近 8 周走势") {
                weekBarChart(statistics.week.weeklyCounts)
                    .frame(height: 180)
            }
            Section("本周每日明细") {
                ForEach(statistics.week.dailyCounts, id: \.day) { dayCount in
                    LabeledContent(dayLabel(dayCount.day), value: "\(dayCount.count)")
                }
            }
        }
    }

    private func monthSection(_ statistics: BoardStatisticsService.Statistics) -> some View {
        Group {
            Section {
                heroCard(count: statistics.month.monthlyCount, title: "本月单数", caption: "历史累计 \(statistics.lifetimeTotal) 单")
                comparisonRow("月对比", statistics.month.comparison)
                metricRow(
                    icon: "clock.fill",
                    title: "本月高峰时段",
                    value: peakHourLabel(statistics.month.peakHour)
                )
                metricRow(icon: "chart.bar.fill", title: "月均单数（近 12 月平均）", value: averageLabel(statistics.month.monthlyAverage))
                metricRow(icon: "trophy.fill", title: "单日最高", value: "\(statistics.month.singleDayHigh)")
            }
            Section("近 12 月走势") {
                monthBarChart(statistics.month.monthlyCounts)
                    .frame(height: 180)
            }
            Section("本月每日明细") {
                ForEach(statistics.month.dailyCounts, id: \.day) { dayCount in
                    LabeledContent(dayLabel(dayCount.day), value: "\(dayCount.count)")
                }
            }
        }
    }

    private func yearSection(_ statistics: BoardStatisticsService.Statistics) -> some View {
        Group {
            Section {
                heroCard(count: statistics.year.yearlyCount, title: "本年度总单数", caption: "历史累计 \(statistics.lifetimeTotal) 单")
                metricRow(icon: "calendar", title: "月均单数（按本年已过月份）", value: averageLabel(statistics.year.monthlyAverage))
                metricRow(icon: "chart.bar.fill", title: "日均单数（按本年已过天数）", value: averageLabel(statistics.year.dailyAverage))
                metricRow(icon: "trophy.fill", title: "单日最高", value: "\(statistics.year.singleDayHigh)")
                metricRow(icon: "crown.fill", title: "单月最高", value: "\(statistics.year.singleMonthHigh)")
                metricRow(
                    icon: "clock.fill",
                    title: "本年高峰时段",
                    value: peakHourLabel(statistics.year.peakHour)
                )
            }
            Section("本年每月单数") {
                monthBarChart(statistics.year.monthlyCounts)
                    .frame(height: 180)
            }
        }
    }

    // MARK: - Cards

    private func heroCard(count: Int, title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
            Text(count, format: .number)
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.orange, Color.red],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .accessibilityElement(children: .combine)
    }

    private func comparisonRow(_ label: String, _ comparison: BoardStatisticsService.PeriodComparison?) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            if let comparison {
                HStack(spacing: 6) {
                    Text("\(comparison.recent) 较 \(comparison.earlier)")
                        .foregroundStyle(.primary)
                    if let percentage = comparison.percentage {
                        Text(percentageLabel(percentage))
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(percentage >= 0 ? Color.green.opacity(0.15) : Color.red.opacity(0.15)))
                            .foregroundStyle(percentage >= 0 ? Color.green : Color.red)
                    }
                }
                .font(.subheadline.weight(.medium))
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metricRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom))
                )
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func percentageLabel(_ percentage: Int) -> String {
        percentage >= 0 ? "↑ \(percentage)%" : "↓ \(abs(percentage))%"
    }

    private func peakHourLabel(_ peakHour: BoardStatisticsService.PeakHour?) -> String {
        guard let peakHour else {
            return "—"
        }
        return String(format: "%02d:00 – %02d:00 · %d 单", peakHour.hour, (peakHour.hour + 1) % 24, peakHour.servedCount)
    }

    private func averageLabel(_ average: Double) -> String {
        average.formatted(.number.precision(.fractionLength(0...1)))
    }

    // MARK: - Chart

    /// Smooth gradient area chart; the highlighted day (today) gets a
    /// marker point so the current progress stands out.
    private func areaChart(_ counts: [BoardStatisticsService.DayCount], highlightedDay: Date) -> some View {
        Chart {
            ForEach(counts, id: \.day) { dayCount in
                AreaMark(
                    x: .value("日期", dayCount.day, unit: .day),
                    y: .value("单数", dayCount.count)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.orange.opacity(0.45), Color.orange.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("日期", dayCount.day, unit: .day),
                    y: .value("单数", dayCount.count)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.orange)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }

            if let today = counts.last(where: { Calendar.current.isDate($0.day, inSameDayAs: highlightedDay) }) {
                PointMark(
                    x: .value("日期", today.day, unit: .day),
                    y: .value("单数", today.count)
                )
                .foregroundStyle(Color.red)
                .symbolSize(90)
                .annotation(position: .top, spacing: 6) {
                    Text("\(today.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.red)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                    .foregroundStyle(.secondary.opacity(0.5))
                AxisValueLabel()
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) {
                AxisValueLabel(format: .dateTime.day(), centered: true)
            }
        }
        .accessibilityLabel(Text("每日单数走势"))
    }

    /// Weekly totals as bars; the x axis labels each week by its Monday
    /// date and the current week is highlighted with a count annotation.
    private func weekBarChart(_ counts: [BoardStatisticsService.WeekCount]) -> some View {
        Chart {
            ForEach(counts, id: \.weekStart) { weekCount in
                BarMark(
                    x: .value("周", weekCount.weekStart, unit: .weekOfYear),
                    y: .value("单数", weekCount.count),
                    width: .ratio(0.55)
                )
                .cornerRadius(5)
                .foregroundStyle(barStyle(isCurrent: counts.last?.weekStart == weekCount.weekStart))
            }
            if let current = counts.last {
                BarMark(
                    x: .value("周", current.weekStart, unit: .weekOfYear),
                    y: .value("单数", current.count),
                    width: .ratio(0.55)
                )
                .opacity(0)
                .annotation(position: .top, spacing: 4) {
                    Text("\(current.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.red)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                    .foregroundStyle(.secondary.opacity(0.5))
                AxisValueLabel()
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear)) {
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: true)
            }
        }
        .accessibilityLabel(Text("近八周每周单数"))
    }

    /// Monthly totals as bars; the x axis shows month numbers and the
    /// current month is highlighted with a count annotation.
    private func monthBarChart(_ counts: [BoardStatisticsService.MonthCount]) -> some View {
        Chart {
            ForEach(counts, id: \.monthStart) { monthCount in
                BarMark(
                    x: .value("月", monthCount.monthStart, unit: .month),
                    y: .value("单数", monthCount.count),
                    width: .ratio(0.55)
                )
                .cornerRadius(5)
                .foregroundStyle(barStyle(isCurrent: counts.last?.monthStart == monthCount.monthStart))
            }
            if let current = counts.last {
                BarMark(
                    x: .value("月", current.monthStart, unit: .month),
                    y: .value("单数", current.count),
                    width: .ratio(0.55)
                )
                .opacity(0)
                .annotation(position: .top, spacing: 4) {
                    Text("\(current.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.red)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                    .foregroundStyle(.secondary.opacity(0.5))
                AxisValueLabel()
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) {
                AxisValueLabel(format: .dateTime.month(.defaultDigits), centered: true)
            }
        }
        .accessibilityLabel(Text("近十二月每月单数"))
    }

    private func barStyle(isCurrent: Bool) -> LinearGradient {
        let colors: [Color] = isCurrent
            ? [Color.orange, Color.red]
            : [Color.orange.opacity(0.55), Color.orange.opacity(0.3)]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private func dayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month().day())
    }
}

#Preview {
    NavigationStack {
        BoardStatisticsView(boardID: UUID(), dependencies: .preview())
    }
}