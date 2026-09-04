import SwiftUI
import UIKit

struct CallingView: View {
    @ObservedObject private var viewModel: CallingViewModel
    @State private var undoConfirmation: UUID?
    @State private var pressedActionID: UUID?

    init(viewModel: CallingViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
    }

    var body: some View {
        content
            .navigationTitle(AppTab.calling.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                #if canImport(AVKit)
                ToolbarItem(placement: .navigationBarLeading) {
                    AudioRoutePickerView()
                        .frame(width: 40, height: 40)
                        .accessibilityLabel(Text("切换输出"))
                }
                #endif
                ToolbarItem(placement: .primaryAction) {
                    CallingToolbarButtons(viewModel: viewModel)
                }
            }
            .confirmationDialog(
                "取消本次呼叫？",
                isPresented: Binding(
                    get: { undoConfirmation != nil },
                    set: { if !$0 { undoConfirmation = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("取消本次呼叫", role: .destructive) {
                    if let actionID = undoConfirmation {
                        Task {
                            await viewModel.undoCall(for: actionID)
                        }
                    }
                    undoConfirmation = nil
                }
                Button("保留", role: .cancel) {
                    undoConfirmation = nil
                }
            } message: {
                Text("将删除该号码今日的所有呼叫记录，今日单数回落。")
            }
            .alert("撤销失败", isPresented: undoFailedBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text("无法删除这条呼叫记录，请稍后再试。")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            loadingView
        case .empty:
            FeatureEmptyStateView(
                systemImage: "speaker.wave.2.fill",
                title: "暂无叫号内容",
                message: "叫号方块将在此显示。"
            )
        case .loaded(let loadedContent):
            loadedView(loadedContent)
        case .failed:
            failedLoadingView
        }
    }

    private var loadingView: some View {
        ScrollView {
            VStack(spacing: 14) {
                ProgressView()

                Button("重新加载") {
                    viewModel.retryLoading()
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failedLoadingView: some View {
        ScrollView {
            VStack(spacing: CallDeskTheme.pageSpacing) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("叫号加载失败")
                    .font(.title2.bold())
                Text("请稍后重试。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("重新加载") {
                    viewModel.retryLoading()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    private func loadedView(_ content: CallingViewModel.Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CallDeskTheme.pageSpacing) {
                boardHeader(content)

                liveCallBanner

                if viewModel.callOutcomeFailure != nil {
                    failureBanner
                }

                if content.actions.isEmpty {
                    emptyBoardView
                } else {
                    actionGrid(content.actions)
                }
            }
            .padding()
        }
    }

    /// A short-lived error that tells the operator the last announcement
    /// did not actually go out, with a button to dismiss it early.
    private var failureBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            Text(failureMessage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)

            Spacer(minLength: 0)

            Button {
                viewModel.dismissCallFailure()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(Text("关闭"))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: CallDeskTheme.cardCornerRadius)
                .fill(Color.red.opacity(0.1))
        )
        .accessibilityElement(children: .contain)
    }

    private var failureMessage: LocalizedStringKey {
        switch viewModel.callOutcomeFailure {
        case .interrupted:
            return "播报被中断，请重试"
        case .failed:
            return "呼叫失败，请重试"
        case nil:
            return ""
        }
    }

    /// One full-width card that doubles as the board switcher: the progress
    /// overview sits on the left and the current board identity on the right,
    /// so the whole row reads as one big, obvious control the operator can tap
    /// anywhere to change boards.
    private func boardHeader(_ content: CallingViewModel.Content) -> some View {
        Picker(
            selection: Binding(
                get: { content.selectedBoardID },
                set: { boardID in
                    Task {
                        await viewModel.selectBoard(id: boardID)
                    }
                }
            )
        ) {
            ForEach(content.boards) { board in
                Text(board.name)
                    .tag(board.id)
            }
        } label: {
            HStack(spacing: 12) {
                if !content.actions.isEmpty {
                    statusOverview
                }

                Spacer(minLength: 8)

                boardIdentity(content)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: CallDeskTheme.cardCornerRadius)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CallDeskTheme.cardCornerRadius)
                    .strokeBorder(Color.accentColor.opacity(0.28), lineWidth: 1)
            )
            .contentShape(
                RoundedRectangle(cornerRadius: CallDeskTheme.cardCornerRadius)
            )
        }
        .pickerStyle(.menu)
        .accessibilityLabel(Text("切换呼叫板"))
    }

    /// The right-hand identity of the board switcher card: a small caption,
    /// the current board name in a bold headline, and a strong up/down
    /// chevron so it clearly reads as a switchable control.
    private func boardIdentity(_ content: CallingViewModel.Content) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 1) {
                Text("当前面板")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(content.selectedBoard?.name ?? "")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.accentColor)
        }
    }

    /// A compact overview of the current board: how many actions were
    /// called so far and, while calls are queued, how many are still
    /// waiting behind the running one. The two-line layout mirrors the
    /// board identity on the right so the card reads as one unit.
    private var statusOverview: some View {
        HStack(spacing: 10) {
            ProgressRing(
                fraction: ProgressRing.fraction(
                    calledCount: viewModel.calledCount,
                    totalCount: viewModel.totalCount
                )
            )
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("已呼叫")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("\(viewModel.calledCount)/\(viewModel.totalCount)")
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            if viewModel.queuedCallCount > 0 {
                Text("等待 \(viewModel.queuedCallCount)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.orange.opacity(0.14)))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                    )
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var undoFailedBinding: Binding<Bool> {
        Binding(
            get: { viewModel.undoFailed },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissUndoFailure()
                }
            }
        )
    }

    /// Shows the current call state and a hint that ties the banner back to
    /// the grid below: calling happens by tapping a tile, and tapping an
    /// active tile again cancels it.
    private var liveCallBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Circle()
                    .fill(viewModel.isCallActive ? Color.indigo : Color.secondary)
                    .frame(width: 10, height: 10)
                Text(liveCallPhaseLabel)
                    .font(.subheadline.weight(.semibold))
            }
            Text("点击方块叫号，再次点击可取消，长按数字最大的已呼叫方块约 1 秒可撤销")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: CallDeskTheme.cardCornerRadius)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
    }

    private var liveCallPhaseLabel: String {
        guard viewModel.isCallActive else {
            return "就绪"
        }
        switch viewModel.liveCall.phase {
        case .playingPrompt, .speaking:
            return "正在播报…"
        default:
            return "准备中…"
        }
    }

    private var emptyBoardView: some View {
        VStack(spacing: CallDeskTheme.pageSpacing) {
            Image(systemName: "square.dashed")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("暂无叫号项")
                .font(.title3.bold())

            Text("此面板还没有叫号项。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity)
        .padding(.vertical, CallDeskTheme.pageSpacing)
    }

    private func actionGrid(_ actions: [CallAction]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180), spacing: CallDeskTheme.pageSpacing)],
            spacing: CallDeskTheme.pageSpacing
        ) {
            ForEach(actions) { action in
                actionTile(action)
            }
        }
    }

    private func actionTile(_ action: CallAction) -> some View {
        VStack(spacing: 4) {
            Text(action.title)
                .font(.system(.title, design: .rounded, weight: .heavy))
                .multilineTextAlignment(.center)

            if CallingTileDetailPolicy.shouldShow(
                for: action,
                isEnabled: viewModel.showsActionDetail
            ) {
                Text(action.speechText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            if !action.isEnabled {
                Text("已禁用")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: CallDeskTheme.minimumActionHeight)
        .background(tileBackground(for: action))
        .contentShape(
            RoundedRectangle(cornerRadius: CallDeskTheme.cardCornerRadius)
        )
        .overlay(selectionBorder(for: action))
        .allowsHitTesting(action.isEnabled)
        .opacity(action.isEnabled ? 1 : 0.5)
        .scaleEffect(isUndoPressed(action) ? 0.96 : 1)
        .animation(.easeOut(duration: 0.15), value: pressedActionID)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("播报通知"))
        .onTapGesture {
            if viewModel.hapticFeedbackEnabled {
                impactOccurred()
            }
            Task {
                await viewModel.callAction(id: action.id)
            }
        }
        .onLongPressGesture(
            minimumDuration: 1.0,
            maximumDistance: 50,
            perform: {
                guard viewModel.isUndoable(actionID: action.id) else {
                    return
                }
                if viewModel.hapticFeedbackEnabled {
                    undoHapticOccurred()
                }
                undoConfirmation = action.id
            },
            onPressingChanged: { isPressing in
                pressedActionID = isPressing ? action.id : nil
            }
        )
    }

    /// Whether the tile is currently being long-pressed to undo its call.
    private func isUndoPressed(_ action: CallAction) -> Bool {
        pressedActionID == action.id && viewModel.isUndoable(actionID: action.id)
    }

    @inline(__always)
    private func undoHapticOccurred() {
        guard HapticFeedbackSupport.isAvailable else {
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// A strong accent border on the tile chosen with the hardware keyboard
    /// or remote, so the operator always sees which tile a confirm key will
    /// trigger.
    @ViewBuilder
    private func selectionBorder(for action: CallAction) -> some View {
        let isSelected = viewModel.selectedActionID == action.id
        RoundedRectangle(cornerRadius: CallDeskTheme.cardCornerRadius)
            .strokeBorder(
                isSelected ? Color.accentColor : .clear,
                lineWidth: 3
            )
            .allowsHitTesting(false)
    }

    /// Resolves the tile background by life cycle: called actions get a
    /// soft sage wash with a checkmark badge, the currently speaking action
    /// gets a breathing indigo wash, requested-but-waiting actions are a
    /// quiet amber, and untouched actions keep the neutral fill. The
    /// in-flight states win over the called tint so a re-called tile still
    /// shows its breathing/queued state while it is running.
    @ViewBuilder
    private func tileBackground(for action: CallAction) -> some View {
        let cornerRadius = CallDeskTheme.cardCornerRadius
        if viewModel.isPending(actionID: action.id) {
            if isActiveCallTile(action) {
                activeCallBackground(cornerRadius: cornerRadius)
            } else {
                queuedBackground(cornerRadius: cornerRadius)
            }
        } else if viewModel.hasBeenCalled(actionID: action.id) {
            calledBackground(cornerRadius: cornerRadius)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(.secondarySystemBackground))
        }
    }

    /// A completed tile gets a gentle sage-to-mint wash, so "already
    /// called" reads as settled and calm instead of a flat green slab.
    private func calledBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(
                    colors: [
                        Color.green.opacity(0.22),
                        Color.mint.opacity(0.10),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.green.opacity(0.30), lineWidth: 1)
            )
    }

    /// The currently speaking tile gets a calm indigo-to-blue wash that
    /// slowly breathes, so the operator's eye lands on it without the
    /// harsh neon border.
    private func activeCallBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(
                    colors: [
                        Color.indigo.opacity(0.30),
                        Color.blue.opacity(0.14),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(BreathingBorder(cornerRadius: cornerRadius))
    }

    /// A requested-but-waiting tile stays a quiet amber so it reads as
    /// "in line" without competing with the speaking tile.
    private func queuedBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.orange.opacity(0.14))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
            )
    }

    private func isActiveCallTile(_ action: CallAction) -> Bool {
        viewModel.isCallActive && viewModel.liveCall.actionID == action.id
    }

    @inline(__always)
    private func impactOccurred() {
        guard HapticFeedbackSupport.isAvailable else {
            return
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}

/// The calling page's reset button and its confirmation state.
struct CallingToolbarButtons: View {
    @ObservedObject var viewModel: CallingViewModel
    @State private var showsResetConfirmation = false

    var body: some View {
        Button {
            if viewModel.hapticFeedbackEnabled {
                impactOccurred()
            }
            showsResetConfirmation = true
        } label: {
            Label("清除已呼叫", systemImage: "arrow.counterclockwise")
        }
        .disabled(viewModel.calledActionIDs.isEmpty)
        .tint(.red)
        // On iPad a confirmation dialog needs the toolbar button as its
        // popover source. Attaching this to the page root loses that
        // anchor and can leave the dialog invisible after the button is
        // tapped.
        .confirmationDialog(
            "清除已呼叫？",
            isPresented: $showsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除", role: .destructive) {
                viewModel.resetCalledActions()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("绿色和橙色标记将恢复默认状态。此操作不可撤销。")
        }
    }

    @inline(__always)
    private func impactOccurred() {
        guard HapticFeedbackSupport.isAvailable else {
            return
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}

#Preview {
    let dependencies = AppDependencies.preview()

    NavigationStack {
        CallingView(viewModel: CallingViewModel(dependencies: dependencies))
    }
}
