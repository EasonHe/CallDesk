import Foundation

#if canImport(AVFAudio)
@preconcurrency import AVFAudio
#endif

/// Plays the short attention tone that precedes an announcement.
@MainActor
protocol PromptTonePlaying: Sendable {
    /// Plays one prompt tone and returns once playback has finished.
    ///
    /// - Parameter volume: A hint in the `0...1` range. Implementations may
    ///   ignore it when the underlying API does not support per-play volume.
    func play(style: PromptToneStyle, volume: Double) async
}

#if canImport(AVFAudio)
/// Plays the app-bundled pickup chime. This deliberately does not use an
/// undocumented iOS system-sound ID, which can be silent on some devices.
@MainActor
final class BundledPromptTonePlayer: PromptTonePlaying {
    private enum Resource {
        static let name = "pickup-chime"
        static let fileExtension = "wav"
        static let gap: TimeInterval = 0.17
    }

    func play(style: PromptToneStyle, volume: Double) async {
        for index in 0..<style.chimeCount {
            await playBundledChime(volume: volume)
            guard index < style.chimeCount - 1 else {
                continue
            }
            try? await Task.sleep(nanoseconds: UInt64(Resource.gap * 1_000_000_000))
        }
    }

    private func playBundledChime(volume: Double) async {
        guard let url = Bundle.main.url(
            forResource: Resource.name,
            withExtension: Resource.fileExtension
        ), let player = try? AVAudioPlayer(contentsOf: url) else {
            return
        }

        player.volume = Float(min(max(volume, 0), 1))
        player.prepareToPlay()
        guard player.play() else {
            return
        }
        try? await Task.sleep(nanoseconds: UInt64(player.duration * 1_000_000_000))
    }
}
#endif

/// Used by previews and tests that should not access audio hardware.
@MainActor
struct SilentPromptTonePlayer: PromptTonePlaying {
    func play(style: PromptToneStyle, volume: Double) async {}
}
