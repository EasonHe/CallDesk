import SwiftUI
import Testing
@testable import CallDesk

@Suite("History result presentation")
struct CallResultPresentationTests {
    @Test("Each result maps to its semantic tint")
    func eachResultMapsToItsSemanticTint() {
        #expect(CallResult.queued.displayTint == .neutral)
        #expect(CallResult.completed.displayTint == .success)
        #expect(CallResult.cancelled.displayTint == .cancelled)
        #expect(CallResult.interrupted.displayTint == .interrupted)
        #expect(CallResult.failed.displayTint == .failure)
    }

    @Test("Every result has a distinct tint")
    func everyResultHasADistinctTint() {
        let tints = CallResult.allCases.map(\.displayTint)
        #expect(Set(tints).count == CallResult.allCases.count)
    }

    @Test("Each tint resolves to a color")
    func eachTintResolvesToAColor() {
        for tint in CallResultTint.allCases {
            #expect(tint.color != .clear)
        }
    }
}
