import Combine
import Foundation
import Testing
@testable import CallDesk

@Suite("Settings stores")
struct SettingsStoreTests {
    // MARK: - Helpers

    /// Runs the given body with a `UserDefaults` suite that is removed
    /// afterwards, so tests never touch the standard defaults.
    private func withTemporaryDefaults(
        _ body: (UserDefaults) throws -> Void
    ) throws {
        let suiteName = "calldesk.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    private func makeModifiedSettings() throws -> CallDeskSettings {
        CallDeskSettings(
            voice: try VoiceSettings(
                localeIdentifier: "zh-CN",
                rate: 0.7,
                pitchMultiplier: 1.4,
                volume: 0.9
            ),
            promptTone: try PromptToneSettings(isEnabled: false, volume: 0.2, delay: 1),
            calling: try CallingSettings(
                activeSpeechPolicy: .queueNext,
                defaultRepeatCount: 2,
                repeatDelay: 3
            ),
            history: try HistorySettings(retentionDays: 30, maximumRecordCount: 100),
            display: try DisplaySettings(recentCallCount: 8)
        )
    }

    // MARK: - UserDefaultsSettingsStore

    @Test("Loading without stored data returns the defaults")
    func loadingWithoutStoredDataReturnsDefaults() throws {
        try withTemporaryDefaults { defaults in
            let store = UserDefaultsSettingsStore(defaults: defaults)

            #expect(store.load() == .default)
        }
    }

    @Test("Saved settings round-trip through UserDefaults")
    func savedSettingsRoundTrip() throws {
        let settings = try makeModifiedSettings()
        try withTemporaryDefaults { defaults in
            let store = UserDefaultsSettingsStore(defaults: defaults)

            store.save(settings)

            #expect(store.load() == settings)
            #expect(UserDefaultsSettingsStore(defaults: defaults).load() == settings)
        }
    }

    @Test("Resetting removes the stored payload")
    func resettingRemovesStoredPayload() throws {
        let settings = try makeModifiedSettings()
        try withTemporaryDefaults { defaults in
            let store = UserDefaultsSettingsStore(defaults: defaults)
            store.save(settings)

            store.reset()

            #expect(store.load() == .default)
            #expect(defaults.data(forKey: UserDefaultsSettingsStore.defaultsKey) == nil)
        }
    }

    @Test("A corrupt payload falls back to the defaults")
    func corruptPayloadFallsBackToDefaults() throws {
        try withTemporaryDefaults { defaults in
            defaults.set(Data("not json".utf8), forKey: UserDefaultsSettingsStore.defaultsKey)
            let store = UserDefaultsSettingsStore(defaults: defaults)

            #expect(store.load() == .default)
        }
    }

    @Test("Missing sections fall back to their defaults while others survive")
    func missingSectionsFallBackToDefaults() throws {
        try withTemporaryDefaults { defaults in
            let payload = """
            {"history": {"retentionDays": 7, "maximumRecordCount": 42}}
            """
            defaults.set(Data(payload.utf8), forKey: UserDefaultsSettingsStore.defaultsKey)
            let store = UserDefaultsSettingsStore(defaults: defaults)

            let loaded = store.load()

            #expect(loaded.history.retentionDays == 7)
            #expect(loaded.history.maximumRecordCount == 42)
            #expect(loaded.voice == .default)
            #expect(loaded.promptTone == .default)
            #expect(loaded.calling == .default)
            #expect(loaded.display == .default)
        }
    }

    @Test("A single corrupt section never discards the other sections")
    func singleCorruptSectionKeepsOtherSections() throws {
        try withTemporaryDefaults { defaults in
            let payload = """
            {
                "voice": {"localeIdentifier": "ja-JP"},
                "display": {"recentCallCount": 3}
            }
            """
            defaults.set(Data(payload.utf8), forKey: UserDefaultsSettingsStore.defaultsKey)
            let store = UserDefaultsSettingsStore(defaults: defaults)

            let loaded = store.load()

            #expect(loaded.voice == .default)
            #expect(loaded.display.recentCallCount == 3)
        }
    }

    @Test("A display payload without an appearance follows the system")
    func displayPayloadWithoutAppearanceFollowsSystem() throws {
        try withTemporaryDefaults { defaults in
            let payload = """
            {
                "display": {"recentCallCount": 4}
            }
            """
            defaults.set(Data(payload.utf8), forKey: UserDefaultsSettingsStore.defaultsKey)
            let store = UserDefaultsSettingsStore(defaults: defaults)

            let loaded = store.load()

            #expect(loaded.display.recentCallCount == 4)
            #expect(loaded.display.appearance == .system)
        }
    }

    @Test("Unknown future sections are ignored")
    func unknownFutureSectionsAreIgnored() throws {
        try withTemporaryDefaults { defaults in
            let payload = """
            {
                "display": {"recentCallCount": 2},
                "futureFeature": {"someFlag": true}
            }
            """
            defaults.set(Data(payload.utf8), forKey: UserDefaultsSettingsStore.defaultsKey)
            let store = UserDefaultsSettingsStore(defaults: defaults)

            let loaded = store.load()

            #expect(loaded.display.recentCallCount == 2)
            #expect(loaded.voice == .default)
        }
    }

    // MARK: - InMemorySettingsStore

    @Test("The in-memory store round-trips settings")
    func inMemoryStoreRoundTrips() throws {
        let settings = try makeModifiedSettings()
        let store = InMemorySettingsStore()
        #expect(store.load() == .default)

        store.save(settings)

        #expect(store.load() == settings)
    }

    @Test("The in-memory store resets to the defaults")
    func inMemoryStoreResetsToDefaults() throws {
        let store = InMemorySettingsStore(settings: try makeModifiedSettings())

        store.reset()

        #expect(store.load() == .default)
    }

    // MARK: - Settings publisher

    /// Collects every value a publisher emits synchronously.
    private func collectValues(
        of store: any SettingsStore,
        during body: () -> Void
    ) -> [CallDeskSettings] {
        var received: [CallDeskSettings] = []
        let subscription = store.settingsPublisher.sink { received.append($0) }
        body()
        withExtendedLifetime(subscription) {}
        return received
    }

    @Test("The in-memory publisher emits the current value and every change")
    func inMemoryPublisherEmitsCurrentValueAndChanges() throws {
        let modified = try makeModifiedSettings()
        let store = InMemorySettingsStore()

        let received = collectValues(of: store) {
            store.save(modified)
            store.reset()
        }

        #expect(received == [.default, modified, .default])
    }

    @Test("The UserDefaults publisher emits the current value and every change")
    func userDefaultsPublisherEmitsCurrentValueAndChanges() throws {
        let modified = try makeModifiedSettings()
        try withTemporaryDefaults { defaults in
            let store = UserDefaultsSettingsStore(defaults: defaults)

            let received = collectValues(of: store) {
                store.save(modified)
                store.reset()
            }

            #expect(received == [.default, modified, .default])
        }
    }

    @Test("The UserDefaults publisher starts with the previously stored settings")
    func userDefaultsPublisherStartsWithStoredSettings() throws {
        let modified = try makeModifiedSettings()
        try withTemporaryDefaults { defaults in
            UserDefaultsSettingsStore(defaults: defaults).save(modified)
            let store = UserDefaultsSettingsStore(defaults: defaults)

            let received = collectValues(of: store) {}

            #expect(received == [modified])
        }
    }
}
