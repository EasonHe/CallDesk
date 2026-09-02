import Foundation
import Testing
@testable import CallDesk

@Suite("Called markers store")
struct CalledMarkersStoreTests {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "CalledMarkersStoreTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    @Test("Starts empty when nothing was stored")
    func startsEmpty() {
        let store = UserDefaultsCalledMarkersStore(defaults: makeDefaults())

        #expect(store.load().isEmpty)
    }

    @Test("Round-trips a stored set")
    func roundTripsStoredSet() {
        let defaults = makeDefaults()
        let store = UserDefaultsCalledMarkersStore(defaults: defaults)
        let actionIDs: Set<UUID> = [UUID(), UUID()]

        store.save(actionIDs)

        #expect(UserDefaultsCalledMarkersStore(defaults: defaults).load() == actionIDs)
    }

    @Test("Saving again replaces the previous set")
    func saveReplacesPreviousSet() {
        let defaults = makeDefaults()
        let store = UserDefaultsCalledMarkersStore(defaults: defaults)

        store.save([UUID()])
        store.save([])

        #expect(store.load().isEmpty)
    }

    @Test("Markers saved earlier the same day survive a reload")
    func keepsMarkersWithinTheSameDay() {
        let defaults = makeDefaults()
        var currentTime = Date()
        let store = UserDefaultsCalledMarkersStore(defaults: defaults, now: { currentTime })
        let actionIDs: Set<UUID> = [UUID(), UUID()]

        store.save(actionIDs)
        currentTime.addTimeInterval(60)

        #expect(store.load() == actionIDs)
    }

    @Test("Markers recorded on a previous day load empty")
    func dropsMarkersFromPreviousDay() {
        let defaults = makeDefaults()
        var currentTime = Date()
        let store = UserDefaultsCalledMarkersStore(defaults: defaults, now: { currentTime })
        store.save([UUID()])

        guard let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: currentTime) else {
            Issue.record("calendar failed")
            return
        }
        currentTime = nextDay

        #expect(store.load().isEmpty)
    }
}
