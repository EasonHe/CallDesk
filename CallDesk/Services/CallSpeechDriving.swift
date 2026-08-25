import Foundation

/// One announcement the calling flow can produce.
///
/// Actions either speak synthesized text or play an imported audio clip; the
/// driver receives whichever form the caller resolved for this utterance.
nonisolated enum CallAnnouncement: Equatable, Sendable {
    case speech(String)
    case audio(URL)
}

/// Produces one announcement for the calling flow.
///
/// The voice and prompt-tone settings arrive with every call, so drivers
/// never cache a startup snapshot; the caller decides which settings apply
/// to the announcement. Implementations must return once the announcement has
/// finished and must throw `CancellationError` when the surrounding task
/// is cancelled.
nonisolated protocol CallSpeechDriving: Sendable {
    func announce(
        _ announcement: CallAnnouncement,
        voice: VoiceSettings,
        promptTone: PromptToneSettings
    ) async throws
}

/// A placeholder driver that only simulates the announcement duration.
///
/// Real playback lives in the AVFoundation-backed driver; this keeps the
/// calling flow observable and cancellable without touching audio hardware.
nonisolated struct SilentCallSpeechDriver: CallSpeechDriving {
    let utteranceDuration: TimeInterval

    init(utteranceDuration: TimeInterval = 1.2) {
        self.utteranceDuration = max(0, utteranceDuration)
    }

    func announce(
        _ announcement: CallAnnouncement,
        voice: VoiceSettings,
        promptTone: PromptToneSettings
    ) async throws {
        try await Task.sleep(nanoseconds: UInt64(utteranceDuration * 1_000_000_000))
    }
}
