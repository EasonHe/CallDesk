import CoreGraphics
import Testing
@testable import CallDesk

@Suite("CallDesk theme")
struct CallDeskThemeTests {
    @Test("Layout constants support readable accessible controls")
    func layoutConstantsSupportAccessibleControls() {
        #expect(CallDeskTheme.pageSpacing > 0)
        #expect(CallDeskTheme.cardCornerRadius > 0)
        #expect(CallDeskTheme.minimumActionHeight >= 44)
        #expect(CallDeskTheme.minimumTouchTargetSize >= 44)
    }
}
