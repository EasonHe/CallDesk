import Foundation
import Testing

@testable import CallDesk

@Suite("CallDesk demo data")
struct CallDeskDemoDataTests {
    @Test("Bundled audio contains the complete 01 through 300 sequence")
    func bundledAudioContainsTheComplete300ClipSequence() {
        let expected = (1...300).map { String(format: "%02d.mp3", $0) }

        #expect(BundledAudioClipCatalog.allClipFileNames == expected)
    }

    @Test("Every demo action resolves its bundled audio clip")
    func demoActionsReferenceBundledAudioClips() {
        let catalog = CallDeskDemoData.makeCatalog(now: .now)
        let unresolvedNames = catalog.actions.compactMap(\.audioFileName)
            .filter { !BundledAudioClipCatalog.contains(clipNamed: $0) }

        #expect(unresolvedNames.isEmpty)
    }

    @Test("Legacy demo clip names map to the current bundled names")
    func legacyClipNamesMapToCurrentNames() {
        #expect(CallDeskDemoData.currentClipName(forLegacyClipName: "001.mp3") == "01.mp3")
        #expect(CallDeskDemoData.currentClipName(forLegacyClipName: "099.mp3") == "99.mp3")
        #expect(CallDeskDemoData.currentClipName(forLegacyClipName: "100.mp3") == nil)
        #expect(CallDeskDemoData.currentClipName(forLegacyClipName: "01.mp3") == nil)
    }
}
