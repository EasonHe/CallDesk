import Testing
@testable import CallDesk

@MainActor
@Suite("Calling screen state")
struct CallingScreenStateTests {
    @Test("An empty load result replaces the initial loading screen state")
    func emptyLoadResultReplacesInitialLoadingState() {
        let screenState = CallingScreenState(initialState: .loading)

        screenState.apply(.empty)

        #expect(screenState.state == .empty)
    }
}
