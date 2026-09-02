import Foundation

/// Plays a single audio clip from a file URL and returns once playback has
/// finished.
///
/// Implementations must throw `CancellationError` when the surrounding task is
/// cancelled so the calling flow can record a cancelled result.
nonisolated protocol AudioClipPlaying: Sendable {
    func play(contentsOf url: URL) async throws
}

/// A clip player that does nothing, for previews and tests.
nonisolated struct SilentAudioClipPlayer: AudioClipPlaying {
    let clipDuration: TimeInterval

    init(clipDuration: TimeInterval = 0) {
        self.clipDuration = max(0, clipDuration)
    }

    func play(contentsOf url: URL) async throws {
        guard clipDuration > 0 else {
            try Task.checkCancellation()
            return
        }
        try await Task.sleep(nanoseconds: UInt64(clipDuration * 1_000_000_000))
    }
}

#if canImport(AVFAudio)
import AVFAudio

/// Plays clips with `AVAudioPlayer`.
///
/// The player has no async API, so completion is bridged through the delegate:
/// `didFinishPlaying` resumes normally. Cancelling the task stops playback
/// immediately and resumes by throwing `CancellationError`.
@MainActor
final class AVAudioClipPlayer: NSObject, AudioClipPlaying {
    private var player: AVAudioPlayer?
    private var activeContinuation: CheckedContinuation<Void, any Error>?
    private var isCancelled = false

    nonisolated func play(contentsOf url: URL) async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await playOnMainActor(contentsOf: url)
        } onCancel: {
            Task { @MainActor in self.stop() }
        }
    }

    private func playOnMainActor(contentsOf url: URL) async throws {
        isCancelled = false
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            guard !isCancelled else {
                continuation.resume(throwing: CancellationError())
                return
            }
            do {
                let newPlayer = try AVAudioPlayer(contentsOf: url)
                newPlayer.delegate = self
                player = newPlayer
                activeContinuation = continuation
                guard newPlayer.play() else {
                    finish(throwing: PlaybackError.couldNotStart)
                    return
                }
            } catch {
                activeContinuation = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func stop() {
        isCancelled = true
        guard activeContinuation != nil else { return }
        player?.stop()
        finish(throwing: CancellationError())
    }

    private func finish(throwing error: (any Error)?) {
        player = nil
        guard let continuation = activeContinuation else { return }
        activeContinuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    enum PlaybackError: Error {
        case couldNotStart
    }
}

extension AVAudioClipPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.finish(throwing: flag ? nil : PlaybackError.couldNotStart)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor in
            self.finish(throwing: error ?? PlaybackError.couldNotStart)
        }
    }
}
#endif
