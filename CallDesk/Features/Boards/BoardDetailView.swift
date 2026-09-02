import SwiftUI

struct BoardDetailView: View {
    private struct EditorConfig: Identifiable {
        let id = UUID()
        let actionID: UUID?
    }

    private struct HistoryRoute: Hashable {
        let boardID: UUID
    }

    /// The statistics entry for archived boards: the main data tab only
    /// lists active boards, so archived ones reach their charts here.
    private struct StatisticsRoute: Hashable {
        let boardID: UUID
    }

    @StateObject private var viewModel: BoardDetailViewModel
    @State private var editorConfig: EditorConfig?
    @State private var isBatchEditorPresented = false
    @State private var isEditMode: EditMode = .inactive
    @State private var selectedActionIDs: Set<UUID> = []
    @State private var isDeleteConfirmationPresented = false
    private let dependencies: AppDependencies
    private let boardID: UUID

    init(boardID: UUID, dependencies: AppDependencies) {
        _viewModel = StateObject(
            wrappedValue: BoardDetailViewModel(boardID: boardID, dependencies: dependencies)
        )
        self.dependencies = dependencies
        self.boardID = boardID
    }

    var body: some View {
        content
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    // Archived boards can still be viewed and cleaned up:
                    // deletion stays available while adding new items is
                    // hidden until the archive flag is cleared.
                    Button {
                        withAnimation {
                            if isEditMode == .active {
                                isEditMode = .inactive
                                selectedActionIDs.removeAll()
                            } else {
                                isEditMode = .active
                            }
                        }
                    } label: {
                        Text(isEditMode == .active ? "完成" : "编辑")
                    }
                    .disabled(!hasActions)

                    if isEditMode == .active {
                        Button {
                            toggleSelectAll()
                        } label: {
                            Text(selectedActionIDs.count == loadedActions?.count ? "取消全选" : "全选")
                        }
                        .disabled(!hasActions)

                        Button {
                            isDeleteConfirmationPresented = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        .disabled(selectedActionIDs.isEmpty)
                        .tint(.red)
                    }

                    if !viewModel.isBoardArchived {
                        Menu {
                            Button {
                                editorConfig = EditorConfig(actionID: nil)
                            } label: {
                                Label("添加叫号项", systemImage: "plus")
                            }

                            Button {
                                isBatchEditorPresented = true
                            } label: {
                                Label("批量添加", systemImage: "plus.rectangle.on.rectangle")
                            }
                        } label: {
                            Label("添加叫号项", systemImage: "plus")
                        }
                    } else {
                        NavigationLink(value: StatisticsRoute(boardID: boardID)) {
                            Label("数据", systemImage: "chart.line.uptrend.xyaxis")
                        }

                        Button {
                            Task {
                                await viewModel.unarchiveBoard()
                            }
                        } label: {
                            Label("取消归档", systemImage: "tray.and.arrow.up")
                        }
                    }

                    NavigationLink(value: HistoryRoute(boardID: boardID)) {
                        Label("日志", systemImage: "clock.arrow.circlepath")
                    }
                }
            }
            .navigationDestination(for: HistoryRoute.self) { route in
                HistoryView(
                    dependencies: dependencies,
                    boardID: route.boardID,
                    isReadOnly: viewModel.isBoardArchived
                )
            }
            .navigationDestination(for: StatisticsRoute.self) { route in
                BoardStatisticsView(boardID: route.boardID, dependencies: dependencies)
                    .navigationTitle("数据")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .sheet(item: $editorConfig) { config in
                actionEditor(for: config)
            }
            .sheet(isPresented: $isBatchEditorPresented) {
                BatchActionEditorView(audioPacks: viewModel.listAudioPacks()) { batch in
                    await viewModel.createActions(batch: batch)
                }
            }
            .alert(
                "删除所选叫号项？",
                isPresented: $isDeleteConfirmationPresented,
                presenting: selectedActionIDs
            ) { _ in
                Button("删除", role: .destructive) {
                    Task {
                        await viewModel.deleteActions(ids: Array(selectedActionIDs))
                        selectedActionIDs.removeAll()
                        isEditMode = .inactive
                    }
                }
                Button("取消", role: .cancel) {}
            } message: { ids in
                Text("将删除 \(ids.count) 个叫号项。")
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
            .task {
                await viewModel.loadIfNeeded()
            }
    }

    private var navigationTitle: Text {
        guard case .loaded(let content) = viewModel.state else {
            return Text("面板")
        }
        return Text(content.board.name)
    }

    private var hasActions: Bool {
        guard case .loaded(let content) = viewModel.state else {
            return false
        }
        return !content.actions.isEmpty
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            FeatureEmptyStateView(
                systemImage: "square.dashed",
                title: "暂无叫号项",
                message: "该面板还没有叫号项。"
            )
        case .loaded(let loadedContent):
            if loadedContent.actions.isEmpty {
                FeatureEmptyStateView(
                    systemImage: "square.dashed",
                    title: "暂无叫号项",
                    message: viewModel.isBoardArchived
                        ? "该面板已归档，暂无叫号项。"
                        : "点右上角 + 为该面板添加叫号项。"
                )
            } else {
                actionList(loadedContent.actions)
            }
        case .failed:
            FeatureErrorStateView {
                Task {
                    await viewModel.load()
                }
            }
        }
    }

    private func actionList(_ actions: [CallAction]) -> some View {
        List {
            ForEach(actions) { action in
                actionRow(action)
            }
            // Archived boards stay deletable but not reorderable.
            .onMove(perform: viewModel.isBoardArchived ? nil : { offsets, destination in
                Task {
                    await viewModel.moveActions(from: offsets, to: destination)
                }
            })
            .onDelete { offsets in
                Task {
                    await viewModel.deleteActions(at: offsets)
                }
            }
        }
        .environment(\.editMode, $isEditMode)
        .onChange(of: isEditMode) { newMode in
            if newMode == .inactive {
                selectedActionIDs.removeAll()
            }
        }
    }

    private var loadedActions: [CallAction]? {
        if case .loaded(let content) = viewModel.state {
            return content.actions
        }
        return nil
    }

    private func toggleSelectAll() {
        guard let actions = loadedActions else { return }
        if selectedActionIDs.count == actions.count {
            selectedActionIDs.removeAll()
        } else {
            selectedActionIDs = Set(actions.map(\.id))
        }
    }

    private func actionRow(_ action: CallAction) -> some View {
        HStack(spacing: CallDeskTheme.pageSpacing) {
            if isEditMode == .active {
                Image(systemName: selectedActionIDs.contains(action.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedActionIDs.contains(action.id) ? Color.accentColor : .secondary)
                    .onTapGesture {
                        if selectedActionIDs.contains(action.id) {
                            selectedActionIDs.remove(action.id)
                        } else {
                            selectedActionIDs.insert(action.id)
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(action.title)
                        .font(.headline)

                    if !action.isEnabled {
                        Text("已禁用")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(.tertiarySystemFill)))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(action.speechText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)

            Spacer()

            Toggle("启用", isOn: enabledBinding(for: action))
                .labelsHidden()
                .disabled(viewModel.isBoardArchived)
                .accessibilityLabel(Text("启用"))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            // A tap opens the editor directly; editing the list in place
            // keeps taps for the selection checkmarks. Archived boards
            // stay read-only, so taps do nothing there.
            guard isEditMode != .active, !viewModel.isBoardArchived else {
                return
            }
            editorConfig = EditorConfig(actionID: action.id)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task {
                    await viewModel.deleteAction(id: action.id)
                }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func enabledBinding(for action: CallAction) -> Binding<Bool> {
        Binding(
            get: { action.isEnabled },
            set: { isEnabled in
                Task {
                    await viewModel.setActionEnabled(isEnabled, actionID: action.id)
                }
            }
        )
    }

    private func actionEditor(for config: EditorConfig) -> some View {
        ActionEditorView(
            title: config.actionID == nil ? "新建叫号项" : "编辑叫号项",
            draft: config.actionID.flatMap { viewModel.draft(forActionID: $0) } ?? .init(),
            onImportAudio: { url in viewModel.importAudioClip(from: url) }
        ) { draft in
            await viewModel.saveAction(draft, editingActionID: config.actionID)
        }
    }

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

    private func message(for error: BoardDetailViewModel.OperationError) -> LocalizedStringKey {
        switch error {
        case .saveFailed:
            return "更改无法保存。"
        case .deleteFailed:
            return "无法删除。"
        case .reorderFailed:
            return "新的排序无法保存。"
        }
    }
}

#Preview {
    NavigationStack {
        BoardDetailView(boardID: UUID(), dependencies: .preview())
    }
}
