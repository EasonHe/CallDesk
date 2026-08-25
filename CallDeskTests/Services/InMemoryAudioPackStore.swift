import Foundation
@testable import CallDesk

/// In-memory implementation of `AudioPackStoring` for tests. Packs are kept
/// in a dictionary keyed by UUID; no disk I/O happens.
nonisolated final class InMemoryAudioPackStore: AudioPackStoring, @unchecked Sendable {
    enum TestError: Error {
        case notSupported
    }

    private var packsByID: [UUID: AudioPack] = [:]
    private var filesByPackID: [UUID: [String: Data]] = [:]
    private let lock = NSLock()

    func importPack(from zipURL: URL, named name: String) throws -> AudioPack {
        throw TestError.notSupported
    }

    func listPacks() -> [AudioPack] {
        lock.lock()
        defer { lock.unlock() }
        return packsByID.values.sorted { $0.createdAt > $1.createdAt }
    }

    func url(forClipNamed fileName: String, inPack packID: UUID) -> URL? {
        // In-memory tests don't need a real URL — return nil to indicate
        // the clip isn't materialized on disk.
        return nil
    }

    func deletePack(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        packsByID.removeValue(forKey: id)
        filesByPackID.removeValue(forKey: id)
    }

    /// Test-only helper: inserts a pack directly without going through the
    /// zip import flow.
    func seed(_ pack: AudioPack, files: [String: Data] = [:]) {
        lock.lock()
        defer { lock.unlock() }
        packsByID[pack.id] = pack
        filesByPackID[pack.id] = files
    }
}
