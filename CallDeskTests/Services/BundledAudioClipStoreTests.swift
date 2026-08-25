import Foundation
import Testing
@testable import CallDesk

struct BundledAudioClipStoreTests {
    @Test
    func resolvesUserImportWhenNoBundledMatch() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let userStore = FileSystemAudioClipStore(directoryURL: tempDir)
        let store = BundledAudioClipStore(userClips: userStore, packs: InMemoryAudioPackStore())

        // Drop a fake audio file and import it through the store.
        let source = tempDir.appendingPathComponent("source.m4a", isDirectory: false)
        try "fake-audio-data".write(to: source, atomically: true, encoding: .utf8)
        let storedName = try store.importClip(from: source)

        let resolved = store.url(forClipNamed: storedName)
        #expect(resolved != nil)
        #expect(resolved?.lastPathComponent == storedName)
    }

    @Test
    func removeIsNoOpForUnknownName() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = BundledAudioClipStore(
            userClips: FileSystemAudioClipStore(directoryURL: tempDir),
            packs: InMemoryAudioPackStore()
        )

        // Removing a name that was never imported must not throw or surface
        // an error — the composite store simply ignores it.
        store.removeClip(named: "does-not-exist.mp3")
    }
}
