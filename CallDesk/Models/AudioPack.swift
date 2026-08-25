import Foundation

/// A user-imported collection of audio clips. Packs are isolated from the
/// built-in catalog and from individually-imported clips so the same file
/// name can safely appear in multiple packs.
nonisolated struct AudioPack: Identifiable, Equatable, Sendable, Codable {
    let id: UUID
    let name: String
    let createdAt: Date
    /// File names (not paths) of the audio clips contained in the pack.
    let clipFileNames: [String]

    init(id: UUID, name: String, createdAt: Date, clipFileNames: [String]) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.clipFileNames = clipFileNames
    }
}
