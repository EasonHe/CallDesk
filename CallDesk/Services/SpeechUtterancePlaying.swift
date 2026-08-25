import Foundation

/// Speaks a single utterance and returns once playback has finished.
///
/// Implementations must throw `CancellationError` when the surrounding task is
/// cancelled so the calling flow can record a cancelled result.
nonisolated protocol SpeechUtterancePlaying: Sendable {
    func play(_ text: String, voice: VoiceSettings) async throws
}

#if canImport(AVFAudio)
import AVFAudio
import Combine

/// Speaks utterances with `AVSpeechSynthesizer`.
///
/// The synthesizer has no async API, so completion is bridged through the
/// delegate: `didFinish` resumes normally and `didCancel` resumes by throwing
/// `CancellationError`. Cancelling the task stops playback immediately.
@MainActor
final class AVSpeechSynthesizerUtterancePlayer: NSObject, SpeechUtterancePlaying {
    private var synthesizer: AVSpeechSynthesizer
    private var activeContinuation: CheckedContinuation<Void, any Error>?
    private var isCancelled = false
    private var resetSubscription: AnyCancellable?

    init(
        synthesizer: AVSpeechSynthesizer = AVSpeechSynthesizer(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.synthesizer = synthesizer
        super.init()
        self.synthesizer.delegate = self
        // After a media services reset every audio object must be rebuilt.
        // The old synthesizer will never call back, so the in-flight
        // utterance ends as cancelled and a fresh synthesizer takes over
        // for the next announcement.
        resetSubscription = notificationCenter
            .publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recoverFromMediaServicesReset()
            }
    }

    private func recoverFromMediaServicesReset() {
        finish(throwing: CancellationError())
        synthesizer.delegate = nil
        synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
    }

    // `play` witnesses a `nonisolated` requirement, so it runs off the main
    // actor and hops onto it to drive the synthesizer safely.
    nonisolated func play(_ text: String, voice: VoiceSettings) async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await speakOnMainActor(text, voice: voice)
        } onCancel: {
            Task { @MainActor in self.stop() }
        }
    }

    private func speakOnMainActor(_ text: String, voice: VoiceSettings) async throws {
        isCancelled = false
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            guard !isCancelled else {
                continuation.resume(throwing: CancellationError())
                return
            }
            activeContinuation = continuation
            synthesizer.speak(makeUtterance(for: text, voice: voice))
        }
    }

    private func stop() {
        isCancelled = true
        guard activeContinuation != nil else { return }
        if !synthesizer.stopSpeaking(at: .immediate) {
            // Nothing was speaking yet, so no delegate callback will arrive.
            finish(throwing: CancellationError())
        }
    }

    private func finish(throwing error: (any Error)?) {
        guard let continuation = activeContinuation else { return }
        activeContinuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    private func makeUtterance(for text: String, voice: VoiceSettings) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: SpeechTextFormatter.speechText(for: text))
        utterance.voice = Self.resolveVoice(for: voice)
        utterance.rate = Float(voice.rate)
        utterance.pitchMultiplier = Float(voice.pitchMultiplier)
        utterance.volume = Float(voice.volume)
        return utterance
    }

    /// Resolves the most natural voice for an announcement: the user's picked
    /// voice while it is still installed, otherwise the best installed Chinese
    /// voice. Announcements always speak Chinese.
    static func resolveVoice(for voice: VoiceSettings) -> AVSpeechSynthesisVoice? {
        if let identifier = voice.voiceIdentifier,
           let pickedVoice = AVSpeechSynthesisVoice(identifier: identifier) {
            return pickedVoice
        }
        if let bestChineseVoice = SystemSpeechVoiceProvider().chineseVoices().first,
           let resolved = AVSpeechSynthesisVoice(identifier: bestChineseVoice.id) {
            return resolved
        }
        return AVSpeechSynthesisVoice(language: "zh-CN")
    }
}

extension AVSpeechSynthesizerUtterancePlayer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish(throwing: nil) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish(throwing: CancellationError()) }
    }
}
#endif
