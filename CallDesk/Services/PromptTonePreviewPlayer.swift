import Foundation

/// Plays a selected prompt-tone style from Settings with the same audible
/// playback session used by real announcements.
@MainActor
protocol PromptTonePreviewPlaying: Sendable {
    func preview(_ tone: PromptToneSettings) async
}

@MainActor
struct SilentPromptTonePreviewPlayer: PromptTonePreviewPlaying {
    func preview(_ tone: PromptToneSettings) async {}
}

/// Settings previews must activate the audio session first. Without that
/// activation an iPhone can mute the system-sound callback even though the
/// real calling path is audible.
@MainActor
final class PromptTonePreviewPlayer: PromptTonePreviewPlaying {
    private let audioSession: any AudioSessionManaging
    private let tonePlayer: any PromptTonePlaying

    init(
        audioSession: any AudioSessionManaging = SystemAudioSessionManager(),
        tonePlayer: any PromptTonePlaying = BundledPromptTonePlayer()
    ) {
        self.audioSession = audioSession
        self.tonePlayer = tonePlayer
    }

    func preview(_ tone: PromptToneSettings) async {
        do {
            try audioSession.activate()
        } catch {
            return
        }
        defer { audioSession.deactivate() }

        await tonePlayer.play(style: tone.style, volume: tone.volume)
    }
}
