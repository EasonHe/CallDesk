import Foundation

/// Stores imported audio clips outside the domain layer so actions only keep
/// a lightweight file-name reference.
///
/// Clips live in a dedicated directory inside Application Support. Importing
/// copies the source file under a fresh, collision-free name and returns that
/// name; the calling flow later resolves the name back to a playable URL.
nonisolated protocol AudioClipStoring: Sendable {
    /// Copies the file at `sourceURL` into managed storage and returns the
    /// stored file name (not a path).
    func importClip(from sourceURL: URL) throws -> String

    /// Resolves a stored file name to a readable URL, or `nil` when the clip
    /// is missing.
    func url(forClipNamed name: String) -> URL?

    /// Removes a stored clip. Missing clips are ignored.
    func removeClip(named name: String)

    /// Lists every user-imported clip currently held in managed storage.
    /// Built-in (bundled) clips are intentionally excluded — they are
    /// read-only and surfaced separately through the catalog.
    func listUserClipNames() -> [String]
}

/// A store backed by the on-disk Application Support directory.
nonisolated final class FileSystemAudioClipStore: AudioClipStoring {
    enum StoreError: Error {
        case couldNotResolveDirectory
        case unreadableSource
    }

    private let directoryURL: URL

    init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let fileManager = FileManager.default
            let base = (try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? fileManager.temporaryDirectory
            self.directoryURL = base.appendingPathComponent("CallAudio", isDirectory: true)
        }
    }

    func importClip(from sourceURL: URL) throws -> String {
        let fileManager = FileManager.default
        try ensureDirectoryExists()

        // Files handed over by the document picker are security-scoped.
        let needsScopedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if needsScopedAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileExtension = sourceURL.pathExtension
        let storedName = fileExtension.isEmpty
            ? UUID().uuidString
            : "\(UUID().uuidString).\(fileExtension)"
        let destinationURL = directoryURL.appendingPathComponent(storedName, isDirectory: false)

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw StoreError.unreadableSource
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return storedName
    }

    func url(forClipNamed name: String) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let candidate = directoryURL.appendingPathComponent(trimmed, isDirectory: false)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    func removeClip(named name: String) {
        guard let clipURL = url(forClipNamed: name) else {
            return
        }
        try? FileManager.default.removeItem(at: clipURL)
    }

    func listUserClipNames() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return names
            .map(\.lastPathComponent)
            .sorted()
    }

    private func ensureDirectoryExists() throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                return
            }
        }
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw StoreError.couldNotResolveDirectory
        }
    }
}
