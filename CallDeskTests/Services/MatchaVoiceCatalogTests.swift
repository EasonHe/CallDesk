import Testing
@testable import CallDesk

@Suite("Matcha voice catalog")
struct MatchaVoiceCatalogTests {
    @Test("The bundled model ships a single Chinese female speaker")
    nonisolated func catalogListsBundledSpeaker() {
        #expect(MatchaVoiceCatalog.speakerNames.count == 1)
        #expect(MatchaVoiceCatalog.speakerNames == ["matcha-zh-baker"])
    }

    @Test("The single speaker maps to speaker ID 0")
    nonisolated func speakerIDMapsToSingleSpeaker() {
        #expect(MatchaVoiceCatalog.speakerID(for: "matcha-zh-baker") == 0)
    }

    @Test("Automatic and stale picks fall back to the bundled speaker")
    nonisolated func unknownPicksFallBackToBundledSpeaker() {
        // Old Kokoro identifiers no longer exist in the Matcha model, so
        // every stale pick resolves to the single bundled speaker (ID 0).
        #expect(MatchaVoiceCatalog.speakerID(for: nil) == 0)
        #expect(MatchaVoiceCatalog.speakerID(for: "zf_001") == 0)
        #expect(MatchaVoiceCatalog.speakerID(for: "com.apple.voice.compact.zh-CN.Tingting") == 0)
    }

    @Test("The provider offers the bundled speaker with a Chinese display name")
    @MainActor
    func providerOffersBundledSpeaker() {
        let options = MatchaVoiceProvider().chineseVoices()
        #expect(options.map(\.id) == MatchaVoiceCatalog.speakerNames)
        #expect(options.map(\.name) == MatchaVoiceCatalog.displayNames)
        #expect(options.allSatisfy { $0.languageCode == "zh-CN" })
        #expect(options.allSatisfy { $0.quality == .premium })
    }

    @Test("Voice settings rate maps onto the Matcha speed scale")
    nonisolated func rateMapsOntoMatchaSpeed() {
        #expect(MatchaUtterancePlayer.speed(forRate: 0.5) == 1.15)
        #expect(MatchaUtterancePlayer.speed(forRate: 1) == 2)
        #expect(MatchaUtterancePlayer.speed(forRate: 0.25) == 0.575)
        // The slider minimum must not freeze playback.
        #expect(MatchaUtterancePlayer.speed(forRate: 0) == 0.5)
    }
}
