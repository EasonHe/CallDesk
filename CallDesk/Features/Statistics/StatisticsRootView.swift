import SwiftUI

/// The data dashboard tab. Statistics are scoped to one board, so the tab
/// shows a board picker when the workspace has more than one and renders
/// `BoardStatisticsView` for the selection.
struct StatisticsRootView: View {
    private let dependencies: AppDependencies
    private let workspaces: any WorkspaceRepository
    private let boards: any CallBoardRepository
    /// Bumped by the app root when the operator returns to this tab so the
    /// board list picks up boards created or deleted elsewhere.
    private let refreshToken: Int

    @State private var state: LoadState = .loading
    @State private var visibleBoards: [CallBoard] = []
    @State private var selectedBoardID: UUID?

    private enum LoadState {
        case loading
        case empty
        case loaded
        case failed
    }

    init(dependencies: AppDependencies, refreshToken: Int = 0) {
        self.dependencies = dependencies
        self.refreshToken = refreshToken
        workspaces = dependencies.workspaces
        boards = dependencies.boards
    }

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                FeatureEmptyStateView(
                    systemImage: "chart.line.uptrend.xyaxis",
                    title: "暂无面板",
                    message: "先在面板标签创建一个叫号面板，数据统计将在此显示。"
                )
            case .loaded:
                loadedView
            case .failed:
                FeatureErrorStateView {
                    Task {
                        await load()
                    }
                }
            }
        }
        .navigationTitle(AppTab.statistics.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
        .onChange(of: refreshToken) { _ in
            Task {
                await load()
            }
        }
    }

    @ViewBuilder
    private var loadedView: some View {
        if let selectedBoardID, visibleBoards.contains(where: { $0.id == selectedBoardID }) {
            VStack(spacing: 0) {
                if visibleBoards.count > 1 {
                    boardPicker
                }
                BoardStatisticsView(
                    boardID: selectedBoardID,
                    dependencies: dependencies,
                    refreshToken: refreshToken
                )
                // A fresh view model per board keeps the period picker
                // and cached counts scoped to the visible selection.
                .id(selectedBoardID)
            }
        }
    }

    private var boardPicker: some View {
        Picker("面板", selection: boardSelection) {
            ForEach(visibleBoards) { board in
                Text(board.name).tag(Optional(board.id))
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityLabel(Text("选择面板"))
    }

    private var boardSelection: Binding<UUID?> {
        Binding(
            get: { selectedBoardID },
            set: { selectedBoardID = $0 }
        )
    }

    private func load() async {
        if visibleBoards.isEmpty {
            state = .loading
        }
        do {
            guard let workspace = try await workspaces.fetchAll().first else {
                state = .empty
                return
            }
            let boards = try await self.boards.fetchAll(
                workspaceID: workspace.id,
                includeArchived: false
            )
            guard !boards.isEmpty else {
                state = .empty
                return
            }
            visibleBoards = boards
            // Keep the current selection when it still exists; a deleted
            // board falls back to the first visible one.
            if let selectedBoardID, boards.contains(where: { $0.id == selectedBoardID }) {
                // Keep it.
            } else {
                selectedBoardID = boards.first?.id
            }
            state = .loaded
        } catch {
            state = .failed
        }
    }
}

#Preview {
    NavigationStack {
        StatisticsRootView(dependencies: .preview())
    }
}
