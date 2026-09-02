import Foundation

/// Drives one announcement using real playback.
///
/// The driver orchestrates the audio session, the optional prompt tone, and a
/// single announcement — either a synthesized utterance or an imported audio
/// clip. `CallService` keeps calling `announce(_:voice:promptTone:)` once per
/// repeat with the settings snapshot of the running session, so this type
/// never stores settings itself and always plays with the values it was
/// handed for the current announcement.
@MainActor
final class AVSpeechSynthesizerSpeechDriver: CallSpeechDriving {
    private let audioSession: any AudioSessionManaging
    private let promptTonePlayer: any PromptTonePlaying
    private let utterancePlayer: any SpeechUtterancePlaying
    private let audioClipPlayer: any AudioClipPlaying
    private let onUtteranceFinished: (@Sendable () -> Void)?

    init(
        audioSession: any AudioSessionManaging,
        promptTonePlayer: any PromptTonePlaying,
        utterancePlayer: any SpeechUtterancePlaying,
        audioClipPlayer: any AudioClipPlaying,
        onUtteranceFinished: (@Sendable () -> Void)? = nil
    ) {
        self.audioSession = audioSession
        self.promptTonePlayer = promptTonePlayer
        self.utterancePlayer = utterancePlayer
        self.audioClipPlayer = audioClipPlayer
        self.onUtteranceFinished = onUtteranceFinished
    }

    func announce(
        _ announcement: CallAnnouncement,
        voice: VoiceSettings,
        promptTone: PromptToneSettings
    ) async throws {
        try Task.checkCancellation()
        try audioSession.activate()
        defer { audioSession.deactivate() }

        if promptTone.isEnabled {
            await promptTonePlayer.play(style: promptTone.style, volume: promptTone.volume)
            try Task.checkCancellation()
            if promptTone.delay > 0 {
                // The configured pause between the prompt tone and the announcement.
                try await Task.sleep(nanoseconds: UInt64(promptTone.delay * 1_000_000_000))
            }
        }

        switch announcement {
        case .speech(let text):
            try await utterancePlayer.play(text, voice: voice)
        case .audio(let url):
            try await audioClipPlayer.play(contentsOf: url)
        }
        onUtteranceFinished?()
    }
}

#if canImport(AVFAudio)
extension AVSpeechSynthesizerSpeechDriver {
    /// Builds a driver wired to the real audio session, bundled prompt tone,
    /// the bundled Matcha voice, and the audio clip player.
    convenience init(onUtteranceFinished: (@Sendable () -> Void)? = nil) {
        self.init(
            audioSession: SystemAudioSessionManager(),
            promptTonePlayer: BundledPromptTonePlayer(),
            utterancePlayer: MatchaUtterancePlayer(),
            audioClipPlayer: AVAudioClipPlayer(),
            onUtteranceFinished: onUtteranceFinished
        )
    }
}
#endif
