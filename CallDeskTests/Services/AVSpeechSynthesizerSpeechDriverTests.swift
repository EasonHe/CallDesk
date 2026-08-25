import Testing
import Foundation
@testable import CallDesk

@MainActor
struct AVSpeechSynthesizerSpeechDriverTests {
    @Test
    func completedCallActivatesSessionPlaysToneThenSpeaks() async throws {
        let fixture = Fixture()
        let driver = fixture.makeDriver()

        try await driver.announce(.speech("Number A1"), voice: fixture.voiceSettings, promptTone: fixture.promptTone())

        #expect(fixture.recorder.events == [
            "activate",
            "tone(style:pickupChime,volume:0.8)",
            "speak(text:Number A1,locale:ja-JP,rate:0.7)",
            "deactivate"
        ])
    }

    @Test
    func disabledPromptToneSkipsTone() async throws {
        let fixture = Fixture()
        let driver = fixture.makeDriver()

        try await driver.announce(
            .speech("Number A1"),
            voice: fixture.voiceSettings,
            promptTone: fixture.promptTone(enabled: false)
        )

        #expect(fixture.recorder.events == [
            "activate",
            "speak(text:Number A1,locale:ja-JP,rate:0.7)",
            "deactivate"
        ])
    }

    @Test
    func configuredPromptToneStyleReachesTheTonePlayer() async throws {
        let fixture = Fixture()
        let driver = fixture.makeDriver()
        let tone = try PromptToneSettings(
            isEnabled: true,
            style: .doubleChime,
            volume: 0.8,
            delay: 0
        )

        try await driver.announce(.speech("Number A1"), voice: fixture.voiceSettings, promptTone: tone)

        #expect(fixture.recorder.events.contains("tone(style:doubleChime,volume:0.8)"))
    }

    @Test
    func eachCallUsesTheSettingsItWasHanded() async throws {
        let fixture = Fixture()
        let driver = fixture.makeDriver()

        try await driver.announce(.speech("Number A1"), voice: fixture.voiceSettings, promptTone: fixture.promptTone())
        let germanVoice = try VoiceSettings(
            localeIdentifier: "de-DE",
            rate: 0.4,
            pitchMultiplier: 1,
            volume: 1
        )
        try await driver.announce(
            .speech("Number A2"),
            voice: germanVoice,
            promptTone: try PromptToneSettings(isEnabled: true, volume: 0.3, delay: 0)
        )

        // The driver holds no settings of its own, so the second call plays
        // with the freshly passed voice and tone values.
        #expect(fixture.recorder.events == [
            "activate",
            "tone(style:pickupChime,volume:0.8)",
            "speak(text:Number A1,locale:ja-JP,rate:0.7)",
            "deactivate",
            "activate",
            "tone(style:pickupChime,volume:0.3)",
            "speak(text:Number A2,locale:de-DE,rate:0.4)",
            "deactivate"
        ])
    }

    @Test
    func utteranceFailureRethrowsAndStillDeactivatesSession() async {
        let fixture = Fixture()
        let driver = fixture.makeDriver(utteranceFails: true)

        await #expect(throws: DriverTestError.self) {
            try await driver.announce(.speech("Number A1"), voice: fixture.voiceSettings, promptTone: fixture.promptTone())
        }
        #expect(fixture.recorder.events.first == "activate")
        #expect(fixture.recorder.events.last == "deactivate")
    }

    @Test
    func audioSessionActivationFailureSkipsSpeechAndDeactivation() async {
        let fixture = Fixture()
        let driver = fixture.makeDriver(activationFails: true)

        await #expect(throws: DriverTestError.self) {
            try await driver.announce(.speech("Number A1"), voice: fixture.voiceSettings, promptTone: fixture.promptTone())
        }
        // Activation threw before the deferred deactivate was registered, so no
        // tone, speech, or deactivation happened.
        #expect(fixture.recorder.events == ["activate"])
    }

    @Test
    func completionCallbackFiresAfterSpeechBeforeDeactivate() async throws {
        let fixture = Fixture()
        let recorder = fixture.recorder
        let driver = fixture.makeDriver(onFinished: { recorder.record("finished") })

        try await driver.announce(.speech("Number A1"), voice: fixture.voiceSettings, promptTone: fixture.promptTone())

        #expect(fixture.recorder.events == [
            "activate",
            "tone(style:pickupChime,volume:0.8)",
            "speak(text:Number A1,locale:ja-JP,rate:0.7)",
            "finished",
            "deactivate"
        ])
    }

    @Test
    func cancellationDuringSpeechDeactivatesSession() async {
        let fixture = Fixture()
        let driver = fixture.makeDriver(blockingUtterance: true)

        let task = Task {
            try await driver.announce(.speech("Number A1"), voice: fixture.voiceSettings, promptTone: fixture.promptTone())
        }
        await fixture.waitUntilRecorded("speak-begin")
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(fixture.recorder.events.last == "deactivate")
    }

    @Test
    func audioAnnouncementPlaysClipInsteadOfSpeaking() async throws {
        let fixture = Fixture()
        let driver = fixture.makeDriver()

        let clipURL = URL(fileURLWithPath: "/tmp/A1.caf")
        try await driver.announce(.audio(clipURL), voice: fixture.voiceSettings, promptTone: fixture.promptTone())

        #expect(fixture.recorder.events == [
            "activate",
            "tone(style:pickupChime,volume:0.8)",
            "clip(A1.caf)",
            "deactivate"
        ])
    }
}

// MARK: - Fixtures

enum DriverTestError: Error, Equatable {
    case audioSession
    case utterance
}

private final class CallEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func record(_ event: String) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }

    var events: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@MainActor
private struct Fixture {
    let recorder = CallEventRecorder()

    var voiceSettings: VoiceSettings {
        (try? VoiceSettings(localeIdentifier: "ja-JP", rate: 0.7, pitchMultiplier: 1, volume: 1)) ?? .default
    }

    func promptTone(enabled: Bool = true) -> PromptToneSettings {
        (try? PromptToneSettings(isEnabled: enabled, volume: 0.8, delay: 0)) ?? .default
    }

    func makeDriver(
        utteranceFails: Bool = false,
        activationFails: Bool = false,
        blockingUtterance: Bool = false,
        onFinished: (@Sendable () -> Void)? = nil
    ) -> AVSpeechSynthesizerSpeechDriver {
        AVSpeechSynthesizerSpeechDriver(
            audioSession: FakeAudioSession(recorder: recorder, failsActivation: activationFails),
            promptTonePlayer: FakePromptTonePlayer(recorder: recorder),
            utterancePlayer: FakeUtterancePlayer(
                recorder: recorder,
                fails: utteranceFails,
                blocks: blockingUtterance
            ),
            audioClipPlayer: FakeAudioClipPlayer(recorder: recorder),
            onUtteranceFinished: onFinished
        )
    }

    func waitUntilRecorded(_ event: String) async {
        for _ in 0..<500 {
            if recorder.events.contains(event) { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}

private struct FakeAudioSession: AudioSessionManaging {
    let recorder: CallEventRecorder
    let failsActivation: Bool

    func activate() throws {
        recorder.record("activate")
        if failsActivation {
            throw DriverTestError.audioSession
        }
    }

    func deactivate() {
        recorder.record("deactivate")
    }
}

@MainActor
private struct FakePromptTonePlayer: PromptTonePlaying {
    let recorder: CallEventRecorder

    func play(style: PromptToneStyle, volume: Double) async {
        recorder.record("tone(style:\(style.rawValue),volume:\(volume))")
    }
}

private struct FakeUtterancePlayer: SpeechUtterancePlaying {
    let recorder: CallEventRecorder
    let fails: Bool
    let blocks: Bool

    func play(_ text: String, voice: VoiceSettings) async throws {
        if blocks {
            recorder.record("speak-begin")
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return
        }
        recorder.record("speak(text:\(text),locale:\(voice.localeIdentifier),rate:\(voice.rate))")
        if fails {
            throw DriverTestError.utterance
        }
    }
}

private struct FakeAudioClipPlayer: AudioClipPlaying {
    let recorder: CallEventRecorder

    func play(contentsOf url: URL) async throws {
        recorder.record("clip(\(url.lastPathComponent))")
    }
}
