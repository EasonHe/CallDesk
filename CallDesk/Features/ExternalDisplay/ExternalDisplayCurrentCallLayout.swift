import CoreGraphics

/// The external display always presents a real pickup number. Once speech
/// finishes, it retains the most recently called number rather than exposing a
/// placeholder state to restaurant guests.
struct ExternalDisplayCurrentCallLayout: Equatable {
    static let liveNumberFontSize: CGFloat = 330

    let title: String
    let titleFontSize: CGFloat

    static func make(for liveCall: LiveCallState, mostRecentNumber: String? = nil) -> Self {
        let retainedNumber = mostRecentNumber ?? "—"

        switch liveCall.phase {
        case .queued, .preparing, .playingPrompt, .speaking:
            return Self(
                title: liveCall.title ?? retainedNumber,
                titleFontSize: liveNumberFontSize
            )
        case .idle, .completed, .cancelled, .interrupted, .failed:
            return Self(title: retainedNumber, titleFontSize: liveNumberFontSize)
        }
    }
}
