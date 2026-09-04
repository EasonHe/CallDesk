import Combine
import SwiftUI
import UIKit

/// The UIKit ownership boundary for the primary calling screen. The host
/// guarantees that iOS 16 receives a concrete replacement view when the
/// long-lived calling view model changes state.
struct CallingView: UIViewControllerRepresentable {
    let viewModel: CallingViewModel

    func makeUIViewController(context: Context) -> CallingRenderHostController {
        CallingRenderHostController(viewModel: viewModel)
    }

    func updateUIViewController(_ controller: CallingRenderHostController, context: Context) {}
}

/// Bridges calling state into a UIKit-owned host. On iOS 16 this avoids
/// relying on a TabView child to observe a long-lived SwiftUI object during
/// its first render.
@MainActor
final class CallingRenderHostController: UIViewController {
    private let viewModel: CallingViewModel
    private let contentHost = UIHostingController(rootView: AnyView(EmptyView()))
    private var subscriptions = Set<AnyCancellable>()
    private var hasRequestedInitialRefresh = false

    private(set) var renderedState: FeatureLoadState<CallingViewModel.Content>

    init(viewModel: CallingViewModel) {
        self.viewModel = viewModel
        renderedState = viewModel.state
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installContentHost()
        subscribeToViewModel()
        render(viewModel.state)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasRequestedInitialRefresh else {
            return
        }
        hasRequestedInitialRefresh = true
        viewModel.requestRefresh()
    }

    private func installContentHost() {
        addChild(contentHost)
        contentHost.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentHost.view)
        NSLayoutConstraint.activate([
            contentHost.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentHost.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentHost.view.topAnchor.constraint(equalTo: view.topAnchor),
            contentHost.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        contentHost.didMove(toParent: self)
    }

    private func subscribeToViewModel() {
        viewModel.$state
            .sink { [weak self] state in
                self?.render(state)
            }
            .store(in: &subscriptions)

        viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.render(self?.viewModel.state)
                }
            }
            .store(in: &subscriptions)
    }

    private func render(_ state: FeatureLoadState<CallingViewModel.Content>?) {
        guard let state else {
            return
        }
        renderedState = state
        contentHost.rootView = AnyView(
            CallingScreenContent(viewModel: viewModel, state: state)
        )
    }
}
