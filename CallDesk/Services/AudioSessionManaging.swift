import Foundation

#if canImport(AVFAudio)
import AVFAudio
#endif

/// Encapsulates the audio session lifecycle used while a call is announced.
///
/// Keeping this behind a protocol lets the speech driver activate playback
/// without depending on `AVAudioSession` directly, which also keeps the
/// calling flow testable.
nonisolated protocol AudioSessionManaging: Sendable {
    /// Prepares the shared audio session for spoken playback.
    func activate() throws
    /// Releases the audio session so other audio can resume.
    func deactivate()
}

#if canImport(AVFAudio)
/// Configures `AVAudioSession` for spoken announcements.
///
/// The session uses the `.playback` category so the announcement plays through
/// the system's current output route, and ducks other audio for clarity.
nonisolated struct SystemAudioSessionManager: AudioSessionManaging {
    func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)
    }

    func deactivate() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
#endif
