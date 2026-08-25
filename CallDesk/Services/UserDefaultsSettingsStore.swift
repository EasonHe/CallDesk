import Combine
import Foundation

/// Persists the app settings as one JSON payload in `UserDefaults`.
///
/// Each settings section is decoded independently: data written by an older
/// app version (with missing sections), an unknown future section, or one
/// corrupt section never discards the remaining sections. Missing or invalid
/// sections simply fall back to their defaults, which keeps the payload
/// backward and forward compatible without touching the settings models.
///
/// `UserDefaults` is thread-safe but not marked `Sendable`, hence the
/// `@unchecked Sendable` conformance.
nonisolated final class UserDefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    static let defaultsKey = "calldesk.settings"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private let subject: CurrentValueSubject<CallDeskSettings, Never>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.subject = CurrentValueSubject(Self.storedSettings(in: defaults))
    }

    var settingsPublisher: AnyPublisher<CallDeskSettings, Never> {
        subject.eraseToAnyPublisher()
    }

    func load() -> CallDeskSettings {
        Self.storedSettings(in: defaults)
    }

    func save(_ settings: CallDeskSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        defaults.set(data, forKey: Self.defaultsKey)
        lock.withLock { subject.send(settings) }
    }

    func reset() {
        defaults.removeObject(forKey: Self.defaultsKey)
        lock.withLock { subject.send(.default) }
    }

    private static func storedSettings(in defaults: UserDefaults) -> CallDeskSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let stored = try? JSONDecoder().decode(StoredSettings.self, from: data) else {
            return .default
        }
        return CallDeskSettings(
            voice: stored.voice ?? .default,
            promptTone: stored.promptTone ?? .default,
            calling: stored.calling ?? .default,
            history: stored.history ?? .default,
            display: stored.display ?? .default
        )
    }

    /// Lenient mirror of `CallDeskSettings` used only for decoding: every
    /// section is optional and a section that fails to decode becomes `nil`
    /// instead of failing the whole payload.
    private struct StoredSettings: Decodable {
        let voice: VoiceSettings?
        let promptTone: PromptToneSettings?
        let calling: CallingSettings?
        let history: HistorySettings?
        let display: DisplaySettings?

        private enum CodingKeys: String, CodingKey {
            case voice
            case promptTone
            case calling
            case history
            case display
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            voice = try? container.decodeIfPresent(VoiceSettings.self, forKey: .voice)
            promptTone = try? container.decodeIfPresent(PromptToneSettings.self, forKey: .promptTone)
            calling = try? container.decodeIfPresent(CallingSettings.self, forKey: .calling)
            history = try? container.decodeIfPresent(HistorySettings.self, forKey: .history)
            display = try? container.decodeIfPresent(DisplaySettings.self, forKey: .display)
        }
    }
}
