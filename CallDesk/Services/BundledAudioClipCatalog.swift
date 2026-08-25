import Foundation

/// Catalogs the audio clips that ship inside the app bundle.
///
/// The bundled clips live under `DefaultAudioClips/` and are named as
/// zero-padded numbers (e.g. `01.mp3`, `168.mp3`). The catalog scans the
/// directory once at launch so the list stays in sync with the bundle
/// contents without a hard-coded manifest.
nonisolated enum BundledAudioClipCatalog {
    /// File names of every bundled clip, sorted numerically.
    static let allClipFileNames: [String] = loadClipFileNames()

    /// Resolves a bundled clip name to a playable URL inside the bundle.
    static func url(forClipNamed name: String) -> URL? {
        guard !name.isEmpty,
              let url = Bundle.main.url(forResource: name, withExtension: nil) else {
            return nil
        }
        return url
    }

    /// Returns `true` when the given file name matches one of the bundled
    /// clips — used to distinguish bundled references from user-imported
    /// clips (which use UUID-based names).
    static func contains(clipNamed name: String) -> Bool {
        !name.isEmpty && allClipFileNames.contains(name)
    }

    private static func loadClipFileNames() -> [String] {
        let bundleURL = Bundle.main.bundleURL
        let names = (try? FileManager.default.contentsOfDirectory(
            at: bundleURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return names
            .map(\.lastPathComponent)
            .filter { $0.hasSuffix(".mp3") }
            .sorted(by: numericNameSort)
    }

    /// Sorts file names by the leading number (1, 2, …, 10, 11, …) instead
    /// of lexicographically, so "10.mp3" follows "9.mp3".
    private static func numericNameSort(_ lhs: String, _ rhs: String) -> Bool {
        let lhsNumber = Int(lhs.split(separator: ".").first ?? "") ?? Int.max
        let rhsNumber = Int(rhs.split(separator: ".").first ?? "") ?? Int.max
        if lhsNumber != rhsNumber {
            return lhsNumber < rhsNumber
        }
        return lhs < rhs
    }
}
