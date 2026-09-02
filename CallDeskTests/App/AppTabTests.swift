import Testing
@testable import CallDesk

@Suite("App tab configuration")
struct AppTabTests {
    @Test("Tabs use the primary navigation order")
    func tabsUsePrimaryNavigationOrder() {
        #expect(AppTab.allCases == [.calling, .statistics, .boards, .settings])
    }

    @Test("Tab identity is available from nonisolated contexts")
    nonisolated func tabIdentityIsAvailableFromNonisolatedContexts() {
        #expect(AppTab.calling.id == .calling)
    }

    @Test("Every tab provides visible metadata", arguments: AppTab.allCases)
    func everyTabProvidesVisibleMetadata(tab: AppTab) {
        #expect(!tab.title.isEmpty)
        #expect(!tab.systemImage.isEmpty)
    }

    @Test("Tabs use the approved system images")
    func tabsUseApprovedSystemImages() {
        #expect(AppTab.calling.systemImage == "speaker.wave.2.fill")
        #expect(AppTab.statistics.systemImage == "chart.line.uptrend.xyaxis")
        #expect(AppTab.boards.systemImage == "square.grid.2x2")
        #expect(AppTab.settings.systemImage == "gearshape")
    }
}
