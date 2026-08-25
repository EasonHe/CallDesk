import Foundation
import os.log

#if canImport(AVFAudio)
@preconcurrency import AVFAudio

/// Speaks utterances with the bundled Matcha Chinese voice.
///
/// Text is rendered off the main actor by the shared `MatchaSynthesizer`
/// and the finished PCM plays through a short-lived `AVAudioEngine`.
/// Cancelling the surrounding task interrupts both phases and surfaces as
/// `CancellationError`, matching the `SpeechUtterancePlaying` contract.
/// If the bundled model cannot be used the player falls back to the system
/// synthesizer so announcements never go silent.
@MainActor
final class MatchaUtterancePlayer: SpeechUtterancePlaying {
    private nonisolated static let log = OSLog(subsystem: "io.wayneho.CallDesk", category: "MatchaUtterancePlayer")

    private let synthesizer: MatchaSynthesizer
    private let fallbackPlayer = AVSpeechSynthesizerUtterancePlayer()
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var activeContinuation: CheckedContinuation<Void, any Error>?
    private var isCancelled = false

    init(synthesizer: MatchaSynthesizer = .shared) {
        self.synthesizer = synthesizer
    }

    /// Matcha reads `speed` where 1 is normal, while `VoiceSettings.rate`
    /// keeps the `AVSpeechUtterance` scale where 0.5 is normal. The default
    /// rate maps to 1.15 so announcements keep the brisk, light tempo
    /// chosen during listening tests.
    nonisolated static func speed(forRate rate: Double) -> Float {
        Float(min(max(rate / 0.5 * 1.15, 0.5), 2))
    }

    /// Appends a playback diagnostic line to a file in the app's temporary
    /// directory so device-side behavior can be inspected by pulling the
    /// file off the device.
    nonisolated private static func logPlayback(_ message: String) {
        let line = "\(Date()): \(message)\n"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("calldesk-playback.log")
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: url)
        }
    }

    // `play` witnesses a `nonisolated` requirement, so it runs off the main
    // actor: generation stays there and only playback hops onto it.
    nonisolated func play(_ text: String, voice: VoiceSettings) async throws {
        os_log(.info, log: Self.log, "play() invoked for text count=%d", text.count)
        try Task.checkCancellation()
        let speech: MatchaSynthesizer.RenderedSpeech
        do {
            os_log(.info, log: Self.log, "rendering speech via Matcha…")
            speech = try await renderSpeech(for: text, voice: voice)
            os_log(.info, log: Self.log, "rendered %d samples @ %.0f Hz", speech.samples.count, speech.sampleRate)
        } catch is CancellationError {
            os_log(.info, log: Self.log, "render cancelled")
            throw CancellationError()
        } catch {
            // The bundled model failed; keep the announcement audible with
            // the system synthesizer instead of going silent.
            os_log(.error, log: Self.log, "Matcha render failed: %{public}@; falling back to AVSpeech", "\(error)")
            Self.logPlayback("FALLBACK AVSpeech, reason: \(error)")
            try await fallbackPlayer.play(text, voice: voice)
            return
        }
        Self.logPlayback("MATCHA OK, formattedText: \(SpeechTextFormatter.speechText(for: text))")
        try Task.checkCancellation()
        do {
            try await withTaskCancellationHandler {
                try await playOnMainActor(speech, voice: voice)
            } onCancel: {
                Task { @MainActor in self.stopPlayback() }
            }
        } catch {
            os_log(.error, log: Self.log, "playback failed: %{public}@; falling back to AVSpeech", "\(error)")
            try await fallbackPlayer.play(text, voice: voice)
        }
    }

    // MARK: - Generation

    private nonisolated func renderSpeech(
        for text: String,
        voice: VoiceSettings
    ) async throws -> MatchaSynthesizer.RenderedSpeech {
        let cancellation = MatchaSynthesizer.CancellationFlag()
        return try await withTaskCancellationHandler {
            try await synthesizer.synthesize(
                SpeechTextFormatter.speechText(for: text),
                speakerID: MatchaVoiceCatalog.speakerID(for: voice.voiceIdentifier),
                speed: Self.speed(forRate: voice.rate),
                cancellation: cancellation
            )
        } onCancel: {
            cancellation.cancel()
        }
    }

    // MARK: - Playback

    private func playOnMainActor(
        _ speech: MatchaSynthesizer.RenderedSpeech,
        voice: VoiceSettings
    ) async throws {
        isCancelled = false
        let rawBuffer = try Self.makeBuffer(for: speech)
        let engine = AVAudioEngine()
        let mixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        let buffer: AVAudioPCMBuffer
        if Self.needsResampling(from: rawBuffer.format, to: mixerFormat) {
            buffer = try Self.resample(rawBuffer, to: mixerFormat)
            os_log(.info, log: Self.log, "resampled %d@%@ → %d@%@",
                   rawBuffer.frameLength, rawBuffer.format,
                   buffer.frameLength, mixerFormat)
        } else {
            buffer = rawBuffer
            os_log(.info, log: Self.log, "built PCM buffer: %d frames @ %@", buffer.frameLength, buffer.format)
        }
        let node = AVAudioPlayerNode()
        engine.attach(node)
        connect(node, to: engine, bufferFormat: buffer.format, pitchMultiplier: voice.pitchMultiplier, softness: voice.softness)
        node.volume = Float(voice.volume)
        try engine.start()
        os_log(.info, log: Self.log, "engine started")
        self.engine = engine
        self.playerNode = node
        defer { tearDownPlayback() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            guard !isCancelled else {
                continuation.resume(throwing: CancellationError())
                return
            }
            activeContinuation = continuation
            node.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] completion in
                Task { @MainActor in
                    os_log(.info, log: Self.log, "buffer completion callback: %d", completion.rawValue)
                    self?.finishPlayback(throwing: nil)
                }
            }
            node.play()
            os_log(.info, log: Self.log, "player node started")
        }
    }

    /// Routes the player node to the main mixer. A pitch effect is inserted
    /// only when the user moved the pitch away from normal. A high-shelf cut
    /// tames the bright iPhone speaker; its strength follows the user's
    /// softness setting (0…1 maps to 0…-6 dB).
    private func connect(
        _ node: AVAudioPlayerNode,
        to engine: AVAudioEngine,
        bufferFormat: AVAudioFormat,
        pitchMultiplier: Double,
        softness: Double
    ) {
        let mixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        let lastNodeBeforeMixer: AVAudioNode
        if pitchMultiplier != 1 {
            let pitchEffect = AVAudioUnitTimePitch()
            // AVAudioUnitTimePitch measures pitch in cents; 1200 cents per octave.
            pitchEffect.pitch = 1200 * log2f(Float(pitchMultiplier))
            engine.attach(pitchEffect)
            engine.connect(node, to: pitchEffect, format: bufferFormat)
            lastNodeBeforeMixer = pitchEffect
        } else {
            lastNodeBeforeMixer = node
        }
        let softnessEQ = makeSoftnessEQ(gain: -6 * softness)
        engine.attach(softnessEQ)
        engine.connect(lastNodeBeforeMixer, to: softnessEQ, format: mixerFormat)
        engine.connect(softnessEQ, to: engine.mainMixerNode, format: mixerFormat)
    }

    /// High-shelf EQ with a negative gain above 10 kHz. The iPhone speaker
    /// exaggerates the air band, which makes the same audio sound harder
    /// than the Mac reference; the cut brings it back in line without
    /// dulling the voice.
    private func makeSoftnessEQ(gain: Double) -> AVAudioUnitEQ {
        let eq = AVAudioUnitEQ(numberOfBands: 1)
        let band = eq.bands[0]
        band.filterType = .highShelf
        band.frequency = 10000
        band.bandwidth = 0.7
        band.gain = Float(gain)
        band.bypass = false
        eq.globalGain = 0
        return eq
    }

    /// Returns true when the buffer format differs from the mixer format in
    /// sample rate or channel count, which would otherwise force AVAudioEngine
    /// to perform on-the-fly conversion that can sound grainy on mono speech.
    private static func needsResampling(from source: AVAudioFormat, to target: AVAudioFormat) -> Bool {
        source.sampleRate != target.sampleRate || source.channelCount != target.channelCount
    }

    /// Converts a PCM buffer from the Matcha model's native format (typically
    /// 22 kHz mono) to the hardware mixer's format using AVAudioConverter.
    private static func resample(
        _ source: AVAudioPCMBuffer,
        to targetFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        guard let converter = AVAudioConverter(from: source.format, to: targetFormat) else {
            throw MatchaSynthesizer.SynthesisError.generationFailed
        }
        // Highest quality interpolation keeps the 22 kHz speech smooth after
        // upsampling; the default quality can make the voice sound grainy
        // through the hardware mixer.
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        let ratio = targetFormat.sampleRate / source.format.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(source.frameCapacity) * ratio)
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
            throw MatchaSynthesizer.SynthesisError.generationFailed
        }
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            outStatus.pointee = .haveData
            return source
        }
        if let conversionError {
            throw conversionError
        }
        guard status != .error else {
            throw MatchaSynthesizer.SynthesisError.generationFailed
        }
        return output
    }

    private static func makeBuffer(for speech: MatchaSynthesizer.RenderedSpeech) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: speech.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(speech.samples.count)),
              let channels = buffer.floatChannelData else {
            throw MatchaSynthesizer.SynthesisError.generationFailed
        }
        speech.samples.withUnsafeBufferPointer { samples in
            guard let baseAddress = samples.baseAddress else { return }
            channels[0].update(from: baseAddress, count: samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(speech.samples.count)
        return buffer
    }

    private func stopPlayback() {
        isCancelled = true
        playerNode?.stop()
        finishPlayback(throwing: CancellationError())
    }

    private func finishPlayback(throwing error: (any Error)?) {
        guard let continuation = activeContinuation else { return }
        activeContinuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    private func tearDownPlayback() {
        playerNode?.stop()
        engine?.stop()
        playerNode = nil
        engine = nil
    }
}
#endif
