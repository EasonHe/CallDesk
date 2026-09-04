import Combine

/// The calling screen's rendered state. Keeping this object with the view
/// makes the first result durable even when an older TabView misses an
/// invalidation from an externally owned view model during startup.
@MainActor
final class CallingScreenState: ObservableObject {
    @Published private(set) var state: FeatureLoadState<CallingViewModel.Content>
    @Published private(set) var revision = 0

    init(initialState: FeatureLoadState<CallingViewModel.Content>) {
        state = initialState
    }

    func apply(_ state: FeatureLoadState<CallingViewModel.Content>) {
        self.state = state
        revision &+= 1
    }

    func invalidate() {
        revision &+= 1
    }
}
