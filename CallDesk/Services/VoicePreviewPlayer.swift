import Foundation
import os.log

#if canImport(AVFAudio)
@preconcurrency import AVFAudio
#endif

/// Plays a short sample announcement so the user can audition a voice.
@MainActor
protocol VoicePreviewPlaying: Sendable {
    /// Speaks the sample and returns when playback finishes (or fails).
    func preview(_ text: String, voice: VoiceSettings) async
}

/// A preview player that does nothing, for previews and tests.
@MainActor
struct SilentVoicePreviewPlayer: VoicePreviewPlaying {
    func preview(_ text: String, voice: VoiceSettings) async {}
}

#if canImport(AVFAudio)
/// Speaks the sample through the real audio session and synthesizer.
/// Starting a new preview cancels the one still playing.
@MainActor
final class SpeechVoicePreviewPlayer: VoicePreviewPlaying {
    private nonisolated static let log = OSLog(subsystem: "io.wayneho.CallDesk", category: "VoicePreviewPlayer")

    private let audioSession: any AudioSessionManaging
    private let utterancePlayer: any SpeechUtterancePlaying
    private var activeTask: Task<Void, Never>?

    init(
        audioSession: any AudioSessionManaging = SystemAudioSessionManager(),
        utterancePlayer: any SpeechUtterancePlaying = MatchaUtterancePlayer()
    ) {
        self.audioSession = audioSession
        self.utterancePlayer = utterancePlayer
    }

    func preview(_ text: String, voice: VoiceSettings) async {
        os_log(.info, log: Self.log, "preview() tapped for voice=%{public}@", voice.voiceIdentifier ?? "automatic")
        activeTask?.cancel()
        let audioSession = self.audioSession
        let utterancePlayer = self.utterancePlayer
        // Mirror the underlying task so the caller awaits the full playback.
        await withTaskCancellationHandler {
            await withCheckedContinuation { (outer: CheckedContinuation<Void, Never>) in
                activeTask = Task {
                    do {
                        try audioSession.activate()
                        os_log(.info, log: Self.log, "audio session activated")
                    } catch {
                        os_log(.error, log: Self.log, "audio session activate failed: %{public}@", "\\(error)")
                        Task { @MainActor in outer.resume() }
                        return
                    }
                    defer { audioSession.deactivate() }
                    do {
                        try await utterancePlayer.play(text, voice: voice)
                        os_log(.info, log: Self.log, "preview playback finished")
                    } catch {
                        os_log(.error, log: Self.log, "preview playback failed: %{public}@", "\\(error)")
                    }
                    Task { @MainActor in outer.resume() }
                }
            }
        } onCancel: {
            Task { @MainActor in
                activeTask?.cancel()
            }
        }
    }
}
#endif
