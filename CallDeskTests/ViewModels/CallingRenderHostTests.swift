import Testing
import UIKit
@testable import CallDesk

@MainActor
@Suite("Calling render host")
struct CallingRenderHostTests {
    @Test("The render host replaces its initial loading snapshot with an empty result")
    func emptyResultReplacesInitialSnapshot() async throws {
        let repositories = try InMemoryRepositories.empty()
        let viewModel = CallingViewModel(
            dependencies: AppDependencies(repositories: repositories)
        )
        let host = CallingRenderHostController(viewModel: viewModel)
        host.loadViewIfNeeded()

        await viewModel.load()

        #expect(host.renderedState == .empty)
    }
}
