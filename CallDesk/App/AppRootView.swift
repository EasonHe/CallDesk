import Combine
import SwiftUI

struct AppRootView: View {
    private let dependencies: AppDependencies
    /// Mirrors the persisted appearance so changes made in Settings restyle
    /// the whole app immediately.
    @State private var appearance: AppearanceMode
    /// The visible system tab.
    @State private var selectedTab: AppTab = .calling
    /// Owned here so it survives tab switches and can be refreshed when the
    /// operator returns from another tab.
    @StateObject private var callingViewModel: CallingViewModel
    /// Bumped whenever the operator opens either primary tab so statistics
    /// re-fetches boards that may have changed elsewhere.
    @State private var statisticsRefreshToken = 0
    /// Used to re-sync the calling panel when the app comes back to the
    /// foreground: called markers expire at midnight, and a suspended app
    /// never runs its own midnight timer.
    @Environment(\.scenePhase) private var scenePhase
    /// False until the background demo-data seed finishes; the screens
    /// below read the seeded boards and records, so they must not render
    /// before it. Plain launches have no seed task and skip straight past.
    @State private var isInitialDataReady: Bool

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _appearance = State(initialValue: dependencies.settingsStore.load().display.appearance)
        _callingViewModel = StateObject(
            wrappedValue: CallingViewModel(dependencies: dependencies)
        )
        _isInitialDataReady = State(initialValue: dependencies.initialDataSeed == nil)
    }

    var body: some View {
        Group {
            if isInitialDataReady {
                content
            } else {
                seedingPlaceholder
            }
        }
        .task {
            if let seed = dependencies.initialDataSeed {
                await seed.value
                isInitialDataReady = true
            }
        }
        // Keep the first responder outside the tab contents for the app's
        // whole life, so hardware keyboard commands stay available.
        .background(
            KeyboardCommandCapture(onCommand: handleKeyboardCommand)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
        .preferredColorScheme(appearance.colorScheme)
        .onReceive(
            dependencies.settingsStore.settingsPublisher.receive(on: RunLoop.main)
        ) { settings in
            appearance = settings.display.appearance
        }
        .onChange(of: selectedTab) { newTab in
            // Only the visible tab may start a repository refresh. On iOS
            // 16, eagerly refreshing the hidden calling tab while loading
            // Statistics made multiple screens contend for one Core Data
            // background context during startup.
            if newTab == .calling {
                statisticsRefreshToken += 1
                callingViewModel.requestRefresh()
            } else if newTab == .statistics {
                statisticsRefreshToken += 1
            }
        }
        .onChange(of: scenePhase) { newPhase in
            // The app can sit suspended across midnight, so returning to the
            // foreground re-syncs daily called markers and statistics.
            guard newPhase == .active else {
                return
            }
            if selectedTab == .calling {
                callingViewModel.requestRefresh()
            } else if selectedTab == .statistics {
                statisticsRefreshToken += 1
            }
        }
    }

    /// Shown while the demo catalog is still being seeded into Core Data;
    /// only used by `-calldesk-demo-seed` builds with an empty store.
    private var seedingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在载入演示数据…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                CallingView(viewModel: callingViewModel)
            }
            .tabItem {
                Label(AppTab.calling.title, systemImage: AppTab.calling.systemImage)
            }
            .tag(AppTab.calling)

            NavigationStack {
                StatisticsRootView(
                    dependencies: dependencies,
                    refreshToken: statisticsRefreshToken,
                    isActive: selectedTab == .statistics
                )
            }
            .tabItem {
                Label(AppTab.statistics.title, systemImage: AppTab.statistics.systemImage)
            }
            .tag(AppTab.statistics)

            NavigationStack {
                BoardsView(
                    dependencies: dependencies,
                    isActive: selectedTab == .boards
                )
            }
            .tabItem {
                Label(AppTab.boards.title, systemImage: AppTab.boards.systemImage)
            }
            .tag(AppTab.boards)

            NavigationStack {
                SettingsView(dependencies: dependencies)
            }
            .tabItem {
                Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage)
            }
            .tag(AppTab.settings)
        }
    }

    /// Routes hardware keyboard events to the calling screen: arrows move
    /// the selection, Return or Space triggers the selected tile.
    private func handleKeyboardCommand(_ command: KeyboardCommandCapture.Command) {
        switch command {
        case .up, .left:
            callingViewModel.selectPreviousAction()
        case .down, .right:
            callingViewModel.selectNextAction()
        case .confirm:
            Task {
                await callingViewModel.callSelectedAction()
            }
        }
    }

}

extension AppearanceMode {
    /// The color scheme override for SwiftUI; `nil` follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

#Preview {
    AppRootView(dependencies: .preview())
}
