import SwiftUI

struct BoardsView: View {
    private struct EditorConfig: Identifiable {
        let id = UUID()
        let boardID: UUID?
    }

    @StateObject private var viewModel: BoardsViewModel
    @State private var editorConfig: EditorConfig?
    /// Drives the drag handles: named "排序" in the toolbar so it is not
    /// mistaken for editing a board's content.
    @State private var listEditMode: EditMode = .inactive

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = StateObject(wrappedValue: BoardsViewModel(dependencies: dependencies))
    }

    var body: some View {
        content
            .navigationTitle(AppTab.boards.title)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation {
                            listEditMode = listEditMode == .active ? .inactive : .active
                        }
                    } label: {
                        Text(listEditMode == .active ? "完成" : "排序")
                    }
                    .disabled(!viewModel.hasBoards)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editorConfig = EditorConfig(boardID: nil)
                    } label: {
                        Label("新建面板", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: UUID.self) { boardID in
                BoardDetailView(boardID: boardID, dependencies: dependencies)
            }
            .sheet(item: $editorConfig) { config in
                boardEditor(for: config)
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
                await viewModel.refresh()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            emptyStateView
        case .loaded:
            if viewModel.hasBoards {
                boardList
            } else {
                emptyStateView
            }
        case .failed:
            FeatureErrorStateView {
                Task {
                    await viewModel.load()
                }
            }
        }
    }

    private var emptyStateView: some View {
        FeatureEmptyStateView(
            systemImage: "square.grid.2x2",
            title: "暂无面板",
            message: "点右上角 + 创建你的第一个面板。"
        )
    }

    private var boardList: some View {
        List {
            Section {
                Toggle("显示已归档", isOn: $viewModel.showsArchived)
            }

            if viewModel.visibleRows.isEmpty {
                Section {
                    Text("所有面板都已归档。")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(viewModel.visibleRows) { row in
                        boardRow(row)
                    }
                    .onMove { offsets, destination in
                        Task {
                            await viewModel.moveBoards(from: offsets, to: destination)
                        }
                    }
                }
            }
        }
        .environment(\.editMode, $listEditMode)
    }

    private func boardRow(_ row: BoardsViewModel.Row) -> some View {
        NavigationLink(value: row.id) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(row.name)
                        .font(.headline)

                    if row.isArchived {
                        Text("已归档")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(.tertiarySystemFill)))
                            .foregroundStyle(.secondary)
                    }
                }

                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("叫号项：\(row.actionCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
        // Every board-level action is exposed here so renaming, archiving
        // and deleting don't depend on discovering the swipe gesture.
        .contextMenu {
            Button {
                editorConfig = EditorConfig(boardID: row.id)
            } label: {
                Label("编辑面板", systemImage: "pencil")
            }

            Button {
                Task {
                    await viewModel.setArchived(!row.isArchived, boardID: row.id)
                }
            } label: {
                Label(row.isArchived ? "取消归档" : "归档", systemImage: "archivebox")
            }

            Button(role: .destructive) {
                Task {
                    await viewModel.deleteBoard(id: row.id)
                }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task {
                    await viewModel.deleteBoard(id: row.id)
                }
            } label: {
                Label("删除", systemImage: "trash")
            }

            Button {
                Task {
                    await viewModel.setArchived(!row.isArchived, boardID: row.id)
                }
            } label: {
                Label(row.isArchived ? "取消归档" : "归档", systemImage: "archivebox")
            }
            .tint(.indigo)
        }
    }

    private func boardEditor(for config: EditorConfig) -> some View {
        BoardEditorView(
            title: config.boardID == nil ? "新建面板" : "编辑面板",
            draft: config.boardID.flatMap { viewModel.draft(forBoardID: $0) } ?? .init()
        ) { draft in
            await viewModel.saveBoard(draft, editingBoardID: config.boardID)
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

    private func message(for error: BoardsViewModel.OperationError) -> LocalizedStringKey {
        switch error {
        case .boardContainsActions:
            return "该面板仍包含叫号项，请先删除叫号项。"
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
        BoardsView(dependencies: .preview())
    }
}
