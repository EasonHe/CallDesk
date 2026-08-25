import Foundation
import Testing
@testable import CallDesk

@MainActor
@Suite("Prompt tone preview player")
struct PromptTonePreviewPlayerTests {
    @Test("Preview activates the audio session before it plays the selected tone")
    func previewActivatesAudioBeforePlayingTone() async {
        let events = PreviewEventLog()
        let player = PromptTonePreviewPlayer(
            audioSession: PreviewAudioSession(events: events),
            tonePlayer: PreviewTonePlayer(events: events)
        )
        let settings = (try? PromptToneSettings(
            style: .doubleChime,
            volume: 0.6,
            delay: 0
        )) ?? .default

        await player.preview(settings)

        #expect(events.values == [
            "activate",
            "tone(style:doubleChime,volume:0.6)",
            "deactivate"
        ])
    }
}

private final class PreviewEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.withLock { storage }
    }

    func append(_ value: String) {
        lock.withLock { storage.append(value) }
    }
}

private struct PreviewAudioSession: AudioSessionManaging {
    let events: PreviewEventLog

    func activate() throws {
        events.append("activate")
    }

    func deactivate() {
        events.append("deactivate")
    }
}

@MainActor
private struct PreviewTonePlayer: PromptTonePlaying {
    let events: PreviewEventLog

    func play(style: PromptToneStyle, volume: Double) async {
        events.append("tone(style:\(style.rawValue),volume:\(volume))")
    }
}
