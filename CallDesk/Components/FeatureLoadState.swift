enum FeatureLoadState<Content: Equatable>: Equatable {
    case loading
    case empty
    case loaded(Content)
    case failed
}
