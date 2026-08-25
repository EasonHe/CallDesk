import Foundation

/// Persists which call actions have been successfully announced, keyed by
/// action ID, so the calling panel can restore its green "already called"
/// tint across app launches.
///
/// ViewModels communicate with this store through the protocol only, so
/// previews and tests can stay fully in memory while production uses the
/// `UserDefaults`-backed implementation.
nonisolated protocol CalledMarkersStoring: Sendable {
    /// The action IDs that have completed a call so far.
    func load() -> Set<UUID>

    /// Replaces the persisted set with the given action IDs.
    func save(_ actionIDs: Set<UUID>)
}

/// Keeps called markers in memory only. Previews and tests use this store so
/// they never read from or write to the real `UserDefaults`.
nonisolated final class InMemoryCalledMarkersStore: CalledMarkersStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storedActionIDs: Set<UUID> = []

    func load() -> Set<UUID> {
        lock.withLock { storedActionIDs }
    }

    func save(_ actionIDs: Set<UUID>) {
        lock.withLock { storedActionIDs = actionIDs }
    }
}

/// Persists called markers as one JSON payload in `UserDefaults`.
///
/// The payload carries the day the markers were recorded so a load on a
/// later day comes back empty: called progress resets automatically for
/// every new business day without any caller-side bookkeeping.
///
/// `UserDefaults` is thread-safe but not marked `Sendable`, hence the
/// `@unchecked Sendable` conformance.
nonisolated final class UserDefaultsCalledMarkersStore: CalledMarkersStoring, @unchecked Sendable {
    static let defaultsKey = "calldesk.calledMarkers"

    private struct Payload: Codable {
        let identifiers: [String]
        let day: Date
    }

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date
    private let lock = NSLock()

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
    }

    func load() -> Set<UUID> {
        lock.withLock {
            guard let data = defaults.data(forKey: Self.defaultsKey),
                  let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
                return []
            }
            // Markers belong to the day they were recorded; a new day
            // starts with a clean calling panel.
            guard calendar.isDate(payload.day, inSameDayAs: now()) else {
                defaults.removeObject(forKey: Self.defaultsKey)
                return []
            }
            return Set(payload.identifiers.compactMap(UUID.init(uuidString:)))
        }
    }

    func save(_ actionIDs: Set<UUID>) {
        lock.withLock {
            let payload = Payload(
                identifiers: actionIDs.map(\.uuidString).sorted(),
                day: now()
            )
            guard let data = try? JSONEncoder().encode(payload) else {
                return
            }
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
