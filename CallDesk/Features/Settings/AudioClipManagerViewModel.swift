import Combine
import Foundation

@MainActor
final class AudioClipManagerViewModel: ObservableObject {
    struct Content: Equatable {
        let bundledCount: Int
        let userClipNames: [String]
        let packs: [AudioPack]
    }

    enum OperationError: Equatable {
        case deleteFailed
        case importFailed
        case packImportFailed
        case duplicatePackName
    }

    @Published private(set) var state: FeatureLoadState<Content> = .loading
    @Published var operationError: OperationError?

    private let audioClips: any AudioClipStoring
    private let audioPacks: any AudioPackStoring

    init(audioClips: any AudioClipStoring, audioPacks: any AudioPackStoring) {
        self.audioClips = audioClips
        self.audioPacks = audioPacks
    }

    func load() {
        let content = Content(
            bundledCount: BundledAudioClipCatalog.allClipFileNames.count,
            userClipNames: audioClips.listUserClipNames(),
            packs: audioPacks.listPacks()
        )
        state = content.userClipNames.isEmpty
            && content.packs.isEmpty
            && content.bundledCount == 0
            ? .empty
            : .loaded(content)
    }

    /// Removes a user-imported clip by name. Bundled clip names are ignored
    /// so the read-only default library can never be modified from here.
    func deleteClip(named name: String) {
        guard !BundledAudioClipCatalog.contains(clipNamed: name) else {
            return
        }
        audioClips.removeClip(named: name)
        load()
    }

    func deleteClips(at offsets: IndexSet) {
        guard case .loaded(let content) = state else {
            return
        }
        for offset in offsets where content.userClipNames.indices.contains(offset) {
            deleteClip(named: content.userClipNames[offset])
        }
    }

    /// Removes an entire pack and every audio file it contains.
    func deletePack(id: UUID) {
        audioPacks.deletePack(id: id)
        load()
    }

    func deletePacks(at offsets: IndexSet) {
        guard case .loaded(let content) = state else {
            return
        }
        for offset in offsets where content.packs.indices.contains(offset) {
            audioPacks.deletePack(id: content.packs[offset].id)
        }
        load()
    }

    /// Imports a picked audio file and refreshes the list. Returns the
    /// stored name on success, `nil` on failure (with `operationError` set).
    func importClip(from sourceURL: URL) -> String? {
        do {
            let name = try audioClips.importClip(from: sourceURL)
            load()
            return name
        } catch {
            operationError = .importFailed
            return nil
        }
    }

    /// Imports a zip archive as a named pack. Returns the created pack on
    /// success. On failure `operationError` is set and `nil` is returned.
    func importPack(from zipURL: URL, named name: String) -> AudioPack? {
        do {
            let pack = try audioPacks.importPack(from: zipURL, named: name)
            load()
            return pack
        } catch FileSystemAudioPackStore.StoreError.duplicateName {
            operationError = .duplicatePackName
            return nil
        } catch {
            operationError = .packImportFailed
            return nil
        }
    }
}
