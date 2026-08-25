import Foundation

/// Quality tiers of a system speech voice, from most to least natural.
nonisolated enum SpeechVoiceQuality: Int, Comparable, Sendable {
    case standard = 0
    case enhanced = 1
    case premium = 2

    static func < (lhs: SpeechVoiceQuality, rhs: SpeechVoiceQuality) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// One installed speech voice the user can pick for announcements.
nonisolated struct SpeechVoiceOption: Identifiable, Equatable, Sendable {
    /// The system voice identifier used to build the utterance voice.
    let id: String
    let name: String
    let quality: SpeechVoiceQuality
    /// The BCP 47 language tag of the voice, such as `zh-CN`.
    let languageCode: String
}

/// Lists the Chinese speech voices installed on the device, best first.
@MainActor
protocol SpeechVoiceProviding {
    func chineseVoices() -> [SpeechVoiceOption]
}

/// A provider with a fixed voice list for previews and tests.
@MainActor
struct FixedSpeechVoiceProvider: SpeechVoiceProviding {
    var voices: [SpeechVoiceOption] = []

    func chineseVoices() -> [SpeechVoiceOption] {
        SpeechVoiceRanking.ranked(voices)
    }
}

/// Orders voices so the most natural Mandarin voice comes first.
nonisolated enum SpeechVoiceRanking {
    static func ranked(_ voices: [SpeechVoiceOption]) -> [SpeechVoiceOption] {
        voices.sorted { lhs, rhs in
            if isMandarin(lhs) != isMandarin(rhs) {
                return isMandarin(lhs)
            }
            if lhs.quality != rhs.quality {
                return lhs.quality > rhs.quality
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func isMandarin(_ voice: SpeechVoiceOption) -> Bool {
        voice.languageCode.hasPrefix("zh-CN")
    }
}

#if canImport(AVFAudio)
import AVFAudio

/// Reads the installed Chinese voices from `AVSpeechSynthesisVoice`.
///
/// Announcements target Mandarin ordering scenarios, so the catalog keeps
/// Mandarin (`zh-CN`) female and gender-neutral voices — Cantonese,
/// Taiwanese, and male voices are noise in the picker. If filtering leaves
/// no Mandarin voice, every Mandarin voice is offered instead.
@MainActor
struct SystemSpeechVoiceProvider: SpeechVoiceProviding {
    func chineseVoices() -> [SpeechVoiceOption] {
        let mandarinVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("zh-CN") }
        let nonMaleVoices = mandarinVoices.filter { $0.gender != .male }
        let offeredVoices = nonMaleVoices.isEmpty ? mandarinVoices : nonMaleVoices
        return SpeechVoiceRanking.ranked(
            offeredVoices.map { voice in
                SpeechVoiceOption(
                    id: voice.identifier,
                    name: voice.name,
                    quality: SpeechVoiceQuality(voice.quality),
                    languageCode: voice.language
                )
            }
        )
    }
}

nonisolated extension SpeechVoiceQuality {
    init(_ quality: AVSpeechSynthesisVoiceQuality) {
        switch quality {
        case .premium:
            self = .premium
        case .enhanced:
            self = .enhanced
        default:
            self = .standard
        }
    }
}
#endif
