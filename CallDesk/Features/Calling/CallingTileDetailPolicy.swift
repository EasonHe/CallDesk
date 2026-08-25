import Foundation

/// Controls whether a calling tile renders its stored speech text below the
/// primary call number. Audio actions retain speech text only as a playback
/// fallback, so it is not operator-facing detail.
nonisolated enum CallingTileDetailPolicy {
    static func shouldShow(for action: CallAction, isEnabled: Bool) -> Bool {
        isEnabled && action.playbackMode == .text && action.speechText != action.title
    }
}
