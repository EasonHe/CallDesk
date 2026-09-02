import Foundation

/// A composite clip store that resolves bundled (read-only) default clips
/// first and falls back to user-imported clips on disk.
///
/// Clip references may address three namespaces:
///   * bundled clips — referenced by their original file name (e.g. `01.mp3`)
///   * user imports  — stored under a UUID on disk
///   * pack clips    — referenced as `<packUUID>/<fileName>`
///
/// The `packID/fileName` form is the only way to address a clip inside a
/// user-imported pack, so the same file name can safely appear in multiple
/// packs without colliding.
nonisolated final class BundledAudioClipStore: AudioClipStoring {
    private let userClips: any AudioClipStoring
    private let packs: any AudioPackStoring

    init(userClips: any AudioClipStoring, packs: any AudioPackStoring) {
        self.userClips = userClips
        self.packs = packs
    }

    func importClip(from sourceURL: URL) throws -> String {
        try userClips.importClip(from: sourceURL)
    }

    func url(forClipNamed name: String) -> URL? {
        // Pack clips are addressed as "<packUUID>/<fileName>". This keeps
        // them in a separate namespace from bundled / single-import clips.
        if let separatorIndex = name.firstIndex(of: "/") {
            let packIDString = String(name[name.startIndex..<separatorIndex])
            let fileName = String(name[name.index(after: separatorIndex)...])
            if let packID = UUID(uuidString: packIDString) {
                return packs.url(forClipNamed: fileName, inPack: packID)
            }
            return nil
        }

        if BundledAudioClipCatalog.contains(clipNamed: name),
           let bundledURL = BundledAudioClipCatalog.url(forClipNamed: name) {
            return bundledURL
        }
        return userClips.url(forClipNamed: name)
    }

    func removeClip(named name: String) {
        // Pack references never target the bundled catalog or the single
        // import store, so short-circuit here.
        if name.contains("/") {
            return
        }
        guard !BundledAudioClipCatalog.contains(clipNamed: name) else {
            return
        }
        userClips.removeClip(named: name)
    }

    func listUserClipNames() -> [String] {
        userClips.listUserClipNames()
    }
}
