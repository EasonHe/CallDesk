import SwiftUI

struct HistoryView: View {
    private enum DeletionTarget: Equatable {
        case records(Set<UUID>)
        case all
    }

    @StateObject private var viewModel: HistoryViewModel
    @State private var selection = Set<UUID>()
    @State private var editMode: EditMode = .inactive
    @State private var deletionTarget: DeletionTarget?
    /// Archived boards open their history read-only: records stay
    /// browsable but deletion and recall entry points disappear.
    private let isReadOnly: Bool

    init(dependencies: AppDependencies, boardID: UUID? = nil, isReadOnly: Bool = false) {
        _viewModel = StateObject(wrappedValue: HistoryViewModel(dependencies: dependencies, boardID: boardID))
        self.isReadOnly = isReadOnly
    }

    var body: some View {
        content
            .navigationTitle("日志")
            .navigationDestination(for: CallRecord.self) { record in
                HistoryDetailView(record: record, viewModel: viewModel, isReadOnly: isReadOnly)
            }
            .searchable(text: $viewModel.searchText, prompt: Text("搜索历史"))
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    filterMenu
                    if hasRecords, !isReadOnly {
                        EditButton()
                    }
                }
            }
            // A toolbar `.bottomBar` sits underneath the floating tab bar
            // and cannot be tapped there, so the edit actions use a safe
            // area inset that stays above the tab bar instead.
            .safeAreaInset(edge: .bottom) {
                if editMode.isEditing {
                    editActionBar
                }
            }
            .environment(\.editMode, $editMode)
            .confirmationDialog(
                confirmationTitle,
                isPresented: deletionDialogBinding,
                titleVisibility: .visible,
                presenting: deletionTarget
            ) { target in
                Button("删除", role: .destructive) {
                    Task {
                        await performDeletion(target)
                    }
                }
            } message: { _ in
                Text("此操作不可撤销。")
            }
            .alert(
                "操作失败",
                isPresented: operationErrorBinding,
                presenting: viewModel.operationError
            ) { _ in
                Button("好", role: .cancel) {}
            } message: { error in
                Text(message(for: error))
            }
            .task(id: viewModel.query) {
                await viewModel.load()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            if viewModel.hasActiveFilters {
                noMatchesView
            } else {
                FeatureEmptyStateView(
                    systemImage: "clock.arrow.circlepath",
                    title: "暂无历史",
                    message: "呼叫历史将显示在此处。"
                )
            }
        case .loaded(let records):
            recordList(records)
        case .failed:
            FeatureErrorStateView {
                Task {
                    await viewModel.load()
                }
            }
        }
    }

    private var hasRecords: Bool {
        if case .loaded = viewModel.state {
            return true
        }
        return false
    }

    private var editActionBar: some View {
        HStack {
            Button("删除所选", role: .destructive) {
                deletionTarget = .records(selection)
            }
            .disabled(selection.isEmpty)

            Spacer()

            Button("清空历史", role: .destructive) {
                deletionTarget = .all
            }
        }
        .padding()
        .background(.bar)
    }

    private var filterMenu: some View {
        Menu {
            Picker("结果", selection: $viewModel.selectedResult) {
                Text("全部结果")
                    .tag(CallResult?.none)
                ForEach(CallResult.allCases, id: \.self) { result in
                    Text(result.displayName)
                        .tag(CallResult?.some(result))
                }
            }

            Picker("时间范围", selection: $viewModel.selectedTimeRange) {
                ForEach(HistoryViewModel.TimeRange.allCases, id: \.self) { timeRange in
                    Text(timeRange.displayName)
                        .tag(timeRange)
                }
            }
        } label: {
            Label("筛选", systemImage: viewModel.hasActiveFilters
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
        }
    }

    private var noMatchesView: some View {
        VStack(spacing: CallDeskTheme.pageSpacing) {
            Image(systemName: "magnifyingglass")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("没有匹配的记录")
                .font(.title3.bold())

            Text("试试调整搜索或筛选条件。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("清除筛选") {
                viewModel.clearFilters()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func recordList(_ records: [CallRecord]) -> some View {
        List(records, selection: $selection) { record in
            NavigationLink(value: record) {
                recordRow(record)
            }
            .cardRowStyle()
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if !isReadOnly {
                    Button("删除", role: .destructive) {
                        deletionTarget = .records([record.id])
                    }
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                if !isReadOnly {
                    Button("再次呼叫") {
                        Task {
                            await viewModel.recall(record)
                        }
                    }
                    .tint(.accentColor)
                }
            }
        }
    }

    private func recordRow(_ record: CallRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.actionTitleSnapshot)
                    .font(.headline)

                if record.repeatIndex > 0 {
                    Text("重复 ×\(record.repeatIndex)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(record.result.displayName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(record.result.displayTint.color.opacity(0.15))
                    )
                    .foregroundStyle(record.result.displayTint.color)
            }

            Text(record.spokenTextSnapshot)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: CallDeskTheme.pageSpacing) {
                Text(record.startedAt, format: .dateTime.year().month().day().hour().minute())
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("history-record-row")
    }

    // MARK: - Deletion

    private var confirmationTitle: LocalizedStringKey {
        switch deletionTarget {
        case .records(let ids) where ids.count > 1:
            "删除选中的历史记录？"
        case .records:
            "删除这条历史记录？"
        case .all, nil:
            "清空全部历史记录？"
        }
    }

    private var deletionDialogBinding: Binding<Bool> {
        Binding(
            get: { deletionTarget != nil },
            set: { isPresented in
                if !isPresented {
                    deletionTarget = nil
                }
            }
        )
    }

    private func performDeletion(_ target: DeletionTarget) async {
        switch target {
        case .records(let ids):
            await viewModel.deleteRecords(ids: ids)
            selection.subtract(ids)
        case .all:
            await viewModel.deleteAllRecords()
            selection.removeAll()
        }
        if !hasRecords {
            editMode = .inactive
        }
    }

    // MARK: - Operation errors

    private var operationErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.operationError != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.operationError = nil
                }
            }
        )
    }

    private func message(for error: HistoryViewModel.OperationError) -> LocalizedStringKey {
        switch error {
        case .deleteFailed:
            "无法删除。"
        case .clearFailed:
            "历史无法清空。"
        case .recallFailed:
            "无法再次呼叫。"
        }
    }
}

extension CallResult {
    var displayName: LocalizedStringKey {
        switch self {
        case .queued:
            "排队中"
        case .completed:
            "已完成"
        case .cancelled:
            "已取消"
        case .interrupted:
            "已中断"
        case .failed:
            "失败"
        }
    }
}

extension HistoryViewModel.TimeRange {
    var displayName: LocalizedStringKey {
        switch self {
        case .all:
            "全部时间"
        case .today:
            "今天"
        case .lastSevenDays:
            "近 7 天"
        case .lastThirtyDays:
            "近 30 天"
        }
    }
}

#Preview {
    NavigationStack {
        HistoryView(dependencies: .preview())
    }
}
