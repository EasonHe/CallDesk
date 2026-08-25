import Foundation

/// Maps the bundled Matcha speaker to a sherpa-onnx speaker ID.
///
/// The `matcha-icefall-zh-baker` model ships a single Chinese female
/// speaker (ID 0). A saved `VoiceSettings.voiceIdentifier` from the old
/// Kokoro catalog no longer matches any speaker, so every pick falls back
/// to the single available voice.
nonisolated enum MatchaVoiceCatalog {
    /// The single bundled speaker, in speaker-ID order.
    static let speakerNames: [String] = [
        "matcha-zh-baker"
    ]

    /// Human-facing name for the voice shown in the Settings picker.
    static let displayNames: [String] = [
        "清甜"
    ]

    /// The speaker ID for a stored voice pick. Automatic (`nil`) and picks
    /// that no longer exist fall back to the single bundled speaker (ID 0).
    static func speakerID(for voiceIdentifier: String?) -> Int32 {
        guard let voiceIdentifier,
              let index = speakerNames.firstIndex(of: voiceIdentifier) else {
            return 0
        }
        return Int32(index)
    }
}

/// Offers the bundled Matcha voice in the Settings voice picker.
@MainActor
struct MatchaVoiceProvider: SpeechVoiceProviding {
    func chineseVoices() -> [SpeechVoiceOption] {
        MatchaVoiceCatalog.speakerNames.enumerated().map { index, id in
            SpeechVoiceOption(
                id: id,
                name: MatchaVoiceCatalog.displayNames[index],
                quality: .premium,
                languageCode: "zh-CN"
            )
        }
    }
}
