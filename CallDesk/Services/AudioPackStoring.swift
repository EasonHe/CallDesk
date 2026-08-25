import Foundation
import Compression

/// Manages user-imported audio packs (zip archives). Each pack lives in its
/// own directory under Application Support, completely isolated from the
/// built-in catalog and from individually-imported clips.
nonisolated protocol AudioPackStoring: Sendable {
    /// Imports a zip archive as a new pack with the given display name.
    /// Returns the created pack.
    func importPack(from zipURL: URL, named name: String) throws -> AudioPack

    /// Lists every imported pack, newest first.
    func listPacks() -> [AudioPack]

    /// Resolves a clip inside a pack to a readable URL.
    func url(forClipNamed fileName: String, inPack packID: UUID) -> URL?

    /// Removes a pack and all of its files from disk.
    func deletePack(id: UUID)
}

/// Unzips a zip archive into a destination directory. Production uses the
/// Compression framework to decode deflate / stored entries; tests inject a
/// fake that materializes a fixed set of entries without touching the disk.
nonisolated protocol AudioUnzipping: Sendable {
    func extractAudioClips(from zipURL: URL, into destination: URL) throws
}

/// Production unzipper that parses the zip archive with `Compression`.
/// Supports method 0 (stored) and method 8 (deflate) — the two methods
/// emitted by Finder / `zip -Z deflate`, which is what users will hand us.
/// Non-audio entries, dot-files, and `__MACOSX` metadata are skipped.
nonisolated struct SystemAudioUnzipper: AudioUnzipping {
    enum UnzipError: Error {
        case unreadableArchive
        case unsupportedCompressionMethod
    }

    func extractAudioClips(from zipURL: URL, into destination: URL) throws {
        let needsScopedAccess = zipURL.startAccessingSecurityScopedResource()
        defer {
            if needsScopedAccess {
                zipURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: zipURL) else {
            throw UnzipError.unreadableArchive
        }

        let entries: [(String, Data)]
        do {
            entries = try ZipReader.readEntries(from: data)
        } catch {
            throw UnzipError.unreadableArchive
        }

        for (name, payload) in entries {
            let lastComponent = (name as NSString).lastPathComponent
            if lastComponent.hasPrefix(".") || lastComponent == "__MACOSX" {
                continue
            }
            guard Self.isAudioFileName(lastComponent) else {
                continue
            }
            let target = destination.appendingPathComponent(lastComponent, isDirectory: false)
            if FileManager.default.fileExists(atPath: target.path) {
                // Same-name audio in nested folders — keep the first one
                // encountered so the pack stays deterministic.
                continue
            }
            try payload.write(to: target, options: .atomic)
        }
    }

    static func isAudioFileName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".mp3")
            || lower.hasSuffix(".m4a")
            || lower.hasSuffix(".wav")
            || lower.hasSuffix(".caf")
            || lower.hasSuffix(".aac")
            || lower.hasSuffix(".aiff")
    }
}

/// Minimal zip reader. Walks the central directory, then for each entry
/// seeks back to its local file header and extracts the payload. Only
/// method 0 (stored) and method 8 (deflate) are supported — everything
/// else throws `unsupportedCompressionMethod`.
nonisolated enum ZipReader {
    enum ZipError: Error {
        case truncated
        case badSignature
        case centralDirectoryNotFound
        case unsupportedCompressionMethod
    }

    nonisolated static func readEntries(from data: Data) throws -> [(String, Data)] {
        guard data.count >= 22 else { throw ZipError.truncated }

        // Locate the End-of-Central-Directory record by scanning backwards
        // for the signature `0x06054b50`.
        var eocdOffset: Int? = nil
        let maxScan = min(data.count, 65_535 + 22)
        var cursor = data.count - 22
        while cursor >= data.count - maxScan {
            if data[cursor] == 0x50, data[cursor + 1] == 0x4b,
               data[cursor + 2] == 0x05, data[cursor + 3] == 0x06 {
                eocdOffset = cursor
                break
            }
            cursor -= 1
        }
        guard let eocd = eocdOffset, eocd + 22 <= data.count else {
            throw ZipError.centralDirectoryNotFound
        }

        let totalEntries = Int(readUInt16(data, eocd + 10))
        let cdSize = Int(readUInt32(data, eocd + 12))
        let cdOffset = Int(readUInt32(data, eocd + 16))
        guard cdOffset + cdSize <= data.count else {
            throw ZipError.truncated
        }

        var entries: [(String, Data)] = []
        entries.reserveCapacity(totalEntries)

        var pointer = cdOffset
        for _ in 0..<totalEntries {
            guard pointer + 46 <= data.count else { throw ZipError.truncated }
            guard readUInt32(data, pointer) == 0x02014b50 else {
                throw ZipError.badSignature
            }
            let method = Int(readUInt16(data, pointer + 10))
            let compressedSize = Int(readUInt32(data, pointer + 20))
            let uncompressedSize = Int(readUInt32(data, pointer + 24))
            let nameLength = Int(readUInt16(data, pointer + 28))
            let extraLength = Int(readUInt16(data, pointer + 30))
            let commentLength = Int(readUInt16(data, pointer + 32))
            let localHeaderOffset = Int(readUInt32(data, pointer + 42))

            let nameStart = pointer + 46
            guard nameStart + nameLength <= data.count else { throw ZipError.truncated }
            let nameData = data.subdata(in: nameStart..<(nameStart + nameLength))
            guard let name = String(data: nameData, encoding: .utf8)
                    ?? String(data: nameData, encoding: .isoLatin1) else {
                throw ZipError.badSignature
            }

            // Seek to the local file header to pull the payload bytes.
            guard localHeaderOffset + 30 <= data.count else { throw ZipError.truncated }
            guard readUInt32(data, localHeaderOffset) == 0x04034b50 else {
                throw ZipError.badSignature
            }
            let localNameLength = Int(readUInt16(data, localHeaderOffset + 26))
            let localExtraLength = Int(readUInt16(data, localHeaderOffset + 28))
            let dataStart = localHeaderOffset + 30 + localNameLength + localExtraLength
            guard dataStart + compressedSize <= data.count else { throw ZipError.truncated }

            let payload: Data
            if !name.hasSuffix("/") && compressedSize > 0 {
                let compressed = data.subdata(in: dataStart..<(dataStart + compressedSize))
                payload = try decompress(compressed: compressed, method: method, uncompressedSize: uncompressedSize)
            } else {
                payload = Data()
            }
            entries.append((name, payload))

            pointer = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    private static func decompress(compressed: Data, method: Int, uncompressedSize: Int) throws -> Data {
        switch method {
        case 0:
            return compressed
        case 8:
            guard uncompressedSize > 0 else { return Data() }
            var output = Data(count: uncompressedSize)
            let decodedCount = output.withUnsafeMutableBytes { outputBuffer in
                compressed.withUnsafeBytes { inputBuffer in
                    compression_decode_buffer(
                        outputBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        outputBuffer.count,
                        inputBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        inputBuffer.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }
            guard decodedCount == uncompressedSize else {
                throw ZipError.unsupportedCompressionMethod
            }
            output.removeSubrange(decodedCount..<output.count)
            return output
        default:
            throw ZipError.unsupportedCompressionMethod
        }
    }

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        let lo = UInt16(data[offset])
        let hi = UInt16(data[offset + 1])
        return lo | (hi << 8)
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }
}

/// File-system-backed implementation. Layout:
///
/// ```
/// Application Support/CallAudio/Packs/
///     <packUUID>/
///         metadata.json   // AudioPack (Codable)
///         01.mp3
///         02.mp3
///         …
/// ```
nonisolated final class FileSystemAudioPackStore: AudioPackStoring {
    enum StoreError: Error {
        case couldNotResolveDirectory
        case unreadableArchive
        case noAudioClipsInArchive
        case duplicateName
    }

    private let baseDirectory: URL
    private let unzipper: any AudioUnzipping

    init(baseDirectory: URL? = nil, unzipper: any AudioUnzipping = SystemAudioUnzipper()) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let fileManager = FileManager.default
            let appSupport = (try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? fileManager.temporaryDirectory
            self.baseDirectory = appSupport
                .appendingPathComponent("CallAudio", isDirectory: true)
                .appendingPathComponent("Packs", isDirectory: true)
        }
        self.unzipper = unzipper
    }

    func importPack(from zipURL: URL, named name: String) throws -> AudioPack {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw StoreError.unreadableArchive
        }
        if listPacks().contains(where: { $0.name == trimmedName }) {
            throw StoreError.duplicateName
        }

        try ensureBaseDirectoryExists()

        let packID = UUID()
        let packDirectory = directoryURL(forPackID: packID)
        try FileManager.default.createDirectory(
            at: packDirectory,
            withIntermediateDirectories: true
        )

        do {
            try unzipper.extractAudioClips(from: zipURL, into: packDirectory)
        } catch {
            try? FileManager.default.removeItem(at: packDirectory)
            throw StoreError.unreadableArchive
        }

        let clipNames = audioFileNames(in: packDirectory)
        guard !clipNames.isEmpty else {
            try? FileManager.default.removeItem(at: packDirectory)
            throw StoreError.noAudioClipsInArchive
        }

        let pack = AudioPack(
            id: packID,
            name: trimmedName,
            createdAt: Date(),
            clipFileNames: clipNames
        )
        try writeMetadata(pack, to: packDirectory)
        return pack
    }

    func listPacks() -> [AudioPack] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return entries.compactMap { url in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return nil
            }
            return readMetadata(from: url)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func url(forClipNamed fileName: String, inPack packID: UUID) -> URL? {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let candidate = directoryURL(forPackID: packID)
            .appendingPathComponent(trimmed, isDirectory: false)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    func deletePack(id: UUID) {
        let url = directoryURL(forPackID: id)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Helpers

    private func directoryURL(forPackID id: UUID) -> URL {
        baseDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func ensureBaseDirectoryExists() throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: baseDirectory.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return
        }
        do {
            try fileManager.createDirectory(
                at: baseDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw StoreError.couldNotResolveDirectory
        }
    }

    private func audioFileNames(in directoryURL: URL) -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return entries
            .map(\.lastPathComponent)
            .filter { $0 != "metadata.json" && SystemAudioUnzipper.isAudioFileName($0) }
            .sorted()
    }

    private func writeMetadata(_ pack: AudioPack, to packDirectory: URL) throws {
        let url = packDirectory.appendingPathComponent("metadata.json", isDirectory: false)
        let data = try JSONEncoder().encode(pack)
        try data.write(to: url, options: .atomic)
    }

    private func readMetadata(from packDirectory: URL) -> AudioPack? {
        let url = packDirectory.appendingPathComponent("metadata.json", isDirectory: false)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(AudioPack.self, from: data)
    }
}
