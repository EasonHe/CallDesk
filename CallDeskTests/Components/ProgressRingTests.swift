import Testing
@testable import CallDesk

@Suite("Progress ring")
struct ProgressRingTests {
    @Test("Nothing called means an empty ring")
    func nothingCalledMeansEmptyRing() {
        #expect(ProgressRing.fraction(calledCount: 0, totalCount: 6) == 0)
    }

    @Test("The fraction is the ratio of called to total")
    func fractionIsRatioOfCalledToTotal() {
        #expect(ProgressRing.fraction(calledCount: 3, totalCount: 6) == 0.5)
    }

    @Test("Everything called fills the ring")
    func everythingCalledFillsTheRing() {
        #expect(ProgressRing.fraction(calledCount: 6, totalCount: 6) == 1)
    }

    @Test("An empty board never draws beyond an empty ring")
    func emptyBoardYieldsZeroFraction() {
        #expect(ProgressRing.fraction(calledCount: 0, totalCount: 0) == 0)
    }

    @Test("The fraction stays within the ring bounds")
    func fractionStaysWithinRingBounds() {
        #expect(ProgressRing.fraction(calledCount: 8, totalCount: 6) == 1)
        #expect(ProgressRing.fraction(calledCount: 1, totalCount: 0) == 0)
    }
}
