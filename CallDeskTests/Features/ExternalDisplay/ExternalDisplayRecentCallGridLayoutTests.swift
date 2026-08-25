import CoreGraphics
import Testing
@testable import CallDesk

@Suite("External display recent-call grid layout")
struct ExternalDisplayRecentCallGridLayoutTests {
    @Test("One through five recent calls use one readable row")
    func compactCountsUseOneRow() {
        let layout = ExternalDisplayRecentCallGridLayout.make(
            in: CGSize(width: 1_477, height: 223),
            itemCount: 5
        )

        #expect(layout.columns == 5)
        #expect(layout.rows == 1)
        #expect(layout.cardSize.width > 250)
        #expect(layout.numberFontSize >= 80)
    }

    @Test("Six through ten recent calls use at most two rows")
    func denseCountsUseTwoRows() {
        let layout = ExternalDisplayRecentCallGridLayout.make(
            in: CGSize(width: 1_477, height: 223),
            itemCount: 10
        )

        #expect(layout.columns == 5)
        #expect(layout.rows == 2)
        #expect(layout.cardSize.height > 80)
        #expect(layout.numberFontSize >= 44)
    }

    @Test("Zero calls produces no grid")
    func zeroCallsProducesNoGrid() {
        let layout = ExternalDisplayRecentCallGridLayout.make(
            in: CGSize(width: 1_477, height: 223),
            itemCount: 0
        )

        #expect(layout.columns == 0)
        #expect(layout.rows == 0)
        #expect(layout.cardSize == .zero)
    }
}
