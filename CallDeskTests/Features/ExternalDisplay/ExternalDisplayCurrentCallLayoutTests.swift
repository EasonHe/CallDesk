import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import CallDesk

@MainActor
@Suite("External display current-call layout")
struct ExternalDisplayCurrentCallLayoutTests {
    @Test("Idle state retains the most recently called pickup number")
    func idleStateRetainsMostRecentPickupNumber() {
        let layout = ExternalDisplayCurrentCallLayout.make(for: .idle, mostRecentNumber: "01")

        #expect(layout.title == "01")
        #expect(layout.titleFontSize == ExternalDisplayCurrentCallLayout.liveNumberFontSize)
    }

    @Test("Active state keeps the live pickup number at the large display scale")
    func activeStateUsesLargePickupNumber() throws {
        let liveCall = try LiveCallState(
            actionID: UUID(),
            title: "A027",
            spokenText: "请 A027 前来取餐",
            phase: .speaking,
            startedAt: .now
        )

        let layout = ExternalDisplayCurrentCallLayout.make(for: liveCall)

        #expect(layout.title == "A027")
        #expect(layout.titleFontSize == ExternalDisplayCurrentCallLayout.liveNumberFontSize)
    }

    @Test("Status-panel boundary bulges into a visible arc at mid-height")
    func statusPanelBoundaryBulgesAtMidHeight() {
        let path = ExternalDisplayStatusPanelShape().path(in: CGRect(x: 0, y: 0, width: 100, height: 100))

        #expect(path.contains(CGPoint(x: 90, y: 50)))
        #expect(!path.contains(CGPoint(x: 90, y: 8)))
    }

    @Test("Recent-call number uses the available card area rather than leaving a large blank center")
    func recentCallNumberUsesReadableDisplayScale() {
        #expect(ExternalDisplayRecentCallLayout.numberFontSize >= 100)
    }
}
