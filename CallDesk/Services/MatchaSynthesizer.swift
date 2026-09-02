import Foundation
import os.log

/// Renders speech with the bundled Matcha model through the sherpa-onnx C API.
///
/// The model weighs about 126 MB (acoustic model + vocoder), so the engine is
/// created lazily on the first request and shared through
/// `MatchaSynthesizer.shared`. The actor serializes synthesis; a running
/// generation can be interrupted through a `CancellationFlag`, which stops
/// the engine at its next progress callback.
actor MatchaSynthesizer {
    private static let log = OSLog(subsystem: "io.wayneho.CallDesk", category: "MatchaSynthesizer")

    /// The app-wide synthesizer so the model is loaded only once.
    static let shared = MatchaSynthesizer()

    /// Warms the engine off the critical path so the first tap-to-speak
    /// returns immediately. The model weighs ~126 MB and takes several
    /// seconds to parse on a cold start; calling this at app launch hides
    /// that latency from the user.
    func preload() {
        os_log(.info, log: Self.log, "preload() starting")
        do {
            _ = try loadedEngine()
            os_log(.info, log: Self.log, "preload() succeeded")
        } catch {
            os_log(.error, log: Self.log, "preload() failed: %{public}@", "\(error)")
        }
    }

    /// PCM rendered for one utterance.
    struct RenderedSpeech: Sendable {
        /// Mono samples in the range -1...1.
        let samples: [Float]
        let sampleRate: Double
    }

    enum SynthesisError: Error {
        case modelResourcesMissing
        case engineCreationFailed
        case generationFailed
    }

    /// Signals a running generation to stop at the next progress callback.
    final class CancellationFlag: @unchecked Sendable {        private let lock = NSLock()
        private var flagged = false

        func cancel() {
            lock.lock()
            flagged = true
            lock.unlock()
        }

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return flagged
        }
    }

    /// Matches the sherpa-onnx default pause between sentences, tuned
    /// tighter than the upstream default so announcements feel snappier.
    private static let silenceScale: Float = 0.05

    /// Called from the generation thread between decoding steps; returning 0
    /// aborts the generation early.
    private static let progressCallback: SherpaOnnxGeneratedAudioProgressCallbackWithArg = { _, _, _, arg in
        guard let arg else { return 1 }
        let flag = Unmanaged<CancellationFlag>.fromOpaque(arg).takeUnretainedValue()
        return flag.isCancelled ? 0 : 1
    }

    // The shared instance lives as long as the app, so the engine is never
    // destroyed; a `deinit` cannot touch this non-Sendable pointer anyway.
    private var engine: OpaquePointer?

    /// The naturalness setting (Matcha `noise_scale`). Changing it rebuilds
    /// the engine so the new voice character applies to the next synthesis.
    private var noiseScale: Double = 0.4

    /// Applies a new naturalness value by rebuilding the engine on the next
    /// request. Lower values sound cleaner, higher values sound breathier
    /// and more human.
    func setNoiseScale(_ scale: Double) {
        let clamped = min(max(scale, 0.1), 0.7)
        guard clamped != noiseScale else { return }
        noiseScale = clamped
        if let engine {
            SherpaOnnxDestroyOfflineTts(engine)
            self.engine = nil
        }
        os_log(.info, log: Self.log, "noise scale set to %.2f; engine rebuilt on next use", clamped)
    }

    /// Renders `text` and returns the finished PCM.
    ///
    /// Throws `CancellationError` when `cancellation` was flagged, so callers
    /// can treat an interrupted announcement like any other cancelled task.
    func synthesize(
        _ text: String,
        speakerID: Int32,
        speed: Float,
        cancellation: CancellationFlag
    ) throws -> RenderedSpeech {
        let engine = try loadedEngine()
        var generation = SherpaOnnxGenerationConfig()
        generation.sid = speakerID
        generation.speed = speed
        generation.silence_scale = Self.silenceScale
        let audio = SherpaOnnxOfflineTtsGenerateWithConfig(
            engine,
            text,
            &generation,
            Self.progressCallback,
            Unmanaged.passUnretained(cancellation).toOpaque()
        )
        guard let audio else {
            throw SynthesisError.generationFailed
        }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }
        if cancellation.isCancelled {
            throw CancellationError()
        }
        let sampleCount = Int(audio.pointee.n)
        guard sampleCount > 0, let samplePointer = audio.pointee.samples else {
            throw SynthesisError.generationFailed
        }
        return RenderedSpeech(
            samples: [Float](UnsafeBufferPointer(start: samplePointer, count: sampleCount)),
            sampleRate: Double(audio.pointee.sample_rate)
        )
    }

    // MARK: - Engine

    private func loadedEngine() throws -> OpaquePointer {
        if let engine {
            return engine
        }
        guard let resources = Bundle.main.url(forResource: "MatchaTTS", withExtension: nil) else {
            os_log(.error, log: Self.log, "MatchaTTS bundle not found in main bundle")
            throw SynthesisError.modelResourcesMissing
        }
        os_log(.info, log: Self.log, "MatchaTTS resources located at %{public}@", resources.path)
        let strings = CStringArena()
        var config = SherpaOnnxOfflineTtsConfig()
        config.model.matcha.acoustic_model = strings.cString(resources.appendingPathComponent("model.onnx").path)
        config.model.matcha.vocoder = strings.cString(resources.appendingPathComponent("vocos-22khz-univ.onnx").path)
        config.model.matcha.lexicon = strings.cString(resources.appendingPathComponent("lexicon.txt").path)
        config.model.matcha.tokens = strings.cString(resources.appendingPathComponent("tokens.txt").path)
        config.model.matcha.noise_scale = Float(noiseScale)
        config.model.matcha.length_scale = 1
        config.model.num_threads = 2
        config.model.provider = strings.cString("cpu")
        config.max_num_sentences = 1
        config.silence_scale = Self.silenceScale
        os_log(.info, log: Self.log, "creating sherpa-onnx engine…")
        let started = Date()
        let created = withExtendedLifetime(strings) {
            SherpaOnnxCreateOfflineTts(&config)
        }
        guard let created else {
            os_log(.error, log: Self.log, "SherpaOnnxCreateOfflineTts returned nil")
            throw SynthesisError.engineCreationFailed
        }
        os_log(.info, log: Self.log, "engine created in %.2f s", Date().timeIntervalSince(started))
        engine = created
        return created
    }
}

/// Owns C copies of Swift strings so a sherpa-onnx config stays valid while
/// the engine is being created.
private nonisolated final class CStringArena {
    private var pointers: [UnsafeMutablePointer<CChar>] = []

    func cString(_ string: String) -> UnsafePointer<CChar> {
        let bytes = Array(string.utf8CString)
        let pointer = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count)
        pointer.initialize(from: bytes, count: bytes.count)
        pointers.append(pointer)
        return UnsafePointer(pointer)
    }

    deinit {
        for pointer in pointers {
            pointer.deallocate()
        }
    }
}
