import Combine
import Foundation

/// Loads and saves the app settings behind a protocol, so views and view
/// models never touch `UserDefaults` directly and previews and tests can
/// stay fully in memory.
nonisolated protocol SettingsStore: Sendable {
    /// Returns the persisted settings, falling back to the defaults when
    /// nothing has been stored yet.
    func load() -> CallDeskSettings

    /// Persists the given settings immediately.
    func save(_ settings: CallDeskSettings)

    /// Removes every persisted value so `load()` returns the defaults again.
    func reset()

    /// Emits the current settings immediately on subscription and again
    /// after every `save` or `reset`, so services and future display
    /// features can react to changes without polling.
    var settingsPublisher: AnyPublisher<CallDeskSettings, Never> { get }
}

/// Keeps settings in memory only. Previews and tests use this store so they
/// never read from or write to the real `UserDefaults`.
nonisolated final class InMemorySettingsStore: SettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private let subject: CurrentValueSubject<CallDeskSettings, Never>

    init(settings: CallDeskSettings = .default) {
        self.subject = CurrentValueSubject(settings)
    }

    var settingsPublisher: AnyPublisher<CallDeskSettings, Never> {
        subject.eraseToAnyPublisher()
    }

    func load() -> CallDeskSettings {
        lock.withLock { subject.value }
    }

    func save(_ settings: CallDeskSettings) {
        lock.withLock { subject.send(settings) }
    }

    func reset() {
        lock.withLock { subject.send(.default) }
    }
}
