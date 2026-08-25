import Combine
import Foundation

@MainActor
final class BoardDetailViewModel: ObservableObject {
    struct Content: Equatable {
        let board: CallBoard
        let actions: [CallAction]
    }

    struct ActionDraft: Equatable {
        var title = ""
        var speechText = ""
        var style: CallActionStyle = .standard
        var playbackMode: CallActionPlaybackMode = .text
        var audioFileName: String?
        var isEnabled = true
    }

    struct BatchDraft: Equatable {
        var prefix = ""
        var count = 10
        var startNumber = 1
        var speechTemplate = defaultSpeechTemplate
        var style: CallActionStyle = .standard
        var playbackMode: CallActionPlaybackMode = .text
        /// The imported audio pack to draw clips from in audio mode. `nil`
        /// means the built-in catalog.
        var audioPackID: UUID?
        var isEnabled = true

        /// Convenience template pre-filled for text announcements so users
        /// never have to type it by hand. Punctuation gets normalized when
        /// the template is rendered, so half-width or full-width commas and
        /// periods both work.
        static let defaultSpeechTemplate = "请，{name} 号，前来取餐。"

        /// The placeholders replaced with the generated name inside
        /// `speechTemplate`. Both spellings are accepted so batch input
        /// matches the built-in voice template convention.
        static let namePlaceholder = "{name}"
        static let numberPlaceholder = "{number}"

        /// Formats a sequence number with a minimum of two digits, growing
        /// naturally beyond that (1 -> "01", 100 -> "100").
        func formattedTitle(for number: Int) -> String {
            prefix.trimmingCharacters(in: .whitespacesAndNewlines) + String(format: "%02d", number)
        }

        /// Resolves the spoken text for a generated name. When no template is
        /// provided the generated name itself is spoken. Half-width commas,
        /// periods, exclamation marks and question marks are converted to
        /// their full-width Chinese equivalents so typos in punctuation never
        /// produce announcements with missing pauses.
        func speechText(for name: String) -> String {
            let template = Self.normalizedPunctuation(speechTemplate)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !template.isEmpty else {
                return name
            }
            var result = template.replacingOccurrences(of: Self.namePlaceholder, with: name)
            result = result.replacingOccurrences(of: Self.numberPlaceholder, with: name)
            return result
        }

        /// Maps half-width punctuation to full-width Chinese punctuation.
        static func normalizedPunctuation(_ text: String) -> String {
            var result = text
            let mappings = [
                ",": "，", ".": "。", "!": "！", "?": "？",
                ":": "：", ";": "；", "(": "（", ")": "）"
            ]
            for (halfWidth, fullWidth) in mappings {
                result = result.replacingOccurrences(of: halfWidth, with: fullWidth)
            }
            return result
        }
    }

    enum OperationError: Equatable {
        case saveFailed
        case deleteFailed
        case reorderFailed
    }

    @Published private(set) var state: FeatureLoadState<Content> = .loading
    @Published var operationError: OperationError?

    private let boardID: UUID
    private let boards: any CallBoardRepository
    private let actions: any CallActionRepository
    private let audioClips: any AudioClipStoring
    private let audioPacks: any AudioPackStoring
    private var hasLoaded = false

    init(
        boardID: UUID,
        boards: any CallBoardRepository,
        actions: any CallActionRepository,
        audioClips: any AudioClipStoring,
        audioPacks: any AudioPackStoring
    ) {
        self.boardID = boardID
        self.boards = boards
        self.actions = actions
        self.audioClips = audioClips
        self.audioPacks = audioPacks
    }

    convenience init(boardID: UUID, dependencies: AppDependencies) {
        self.init(
            boardID: boardID,
            boards: dependencies.boards,
            actions: dependencies.actions,
            audioClips: dependencies.audioClips,
            audioPacks: dependencies.audioPacks
        )
    }

    /// Every imported audio pack, for the batch editor's source picker.
    func listAudioPacks() -> [AudioPack] {
        audioPacks.listPacks()
    }

    /// Archived boards open read-only: the detail page shows data and
    /// history but hides every mutation entry point.
    var isBoardArchived: Bool {
        guard case .loaded(let content) = state else {
            return false
        }
        return content.board.isArchived
    }

    /// Clears the archive flag so the board becomes editable again. The
    /// only mutation allowed while a board is archived.
    func unarchiveBoard() async {
        guard case .loaded(let content) = state else {
            operationError = .saveFailed
            return
        }
        let board = content.board
        guard board.isArchived else {
            return
        }
        do {
            let updated = try CallBoard(
                id: board.id,
                workspaceID: board.workspaceID,
                name: board.name,
                subtitle: board.subtitle,
                sortOrder: board.sortOrder,
                preferredColumnCount: board.preferredColumnCount,
                showsRecentCalls: board.showsRecentCalls,
                isArchived: false,
                createdAt: board.createdAt,
                updatedAt: max(Date(), board.createdAt)
            )
            try await boards.save(updated)
            await reloadContent()
        } catch {
            operationError = .saveFailed
        }
    }

    func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }
        await load()
    }

    func load() async {
        hasLoaded = true
        state = .loading
        await reloadContent()
    }

    func draft(forActionID id: UUID) -> ActionDraft? {
        guard let action = loadedAction(id: id) else {
            return nil
        }
        return ActionDraft(
            title: action.title,
            speechText: action.speechText,
            style: action.style,
            playbackMode: action.playbackMode,
            audioFileName: action.audioFileName,
            isEnabled: action.isEnabled
        )
    }

    /// Copies a picked audio file into managed storage and returns its stored
    /// name for the draft. Returns `nil` and flags an error when the import
    /// fails so the caller can keep the previous selection.
    func importAudioClip(from sourceURL: URL) -> String? {
        do {
            return try audioClips.importClip(from: sourceURL)
        } catch {
            operationError = .saveFailed
            return nil
        }
    }

    @discardableResult
    func saveAction(_ draft: ActionDraft, editingActionID: UUID?) async -> Bool {
        guard case .loaded(let content) = state else {
            operationError = .saveFailed
            return false
        }

        do {
            let now = Date()
            if let editingActionID {
                guard let existing = loadedAction(id: editingActionID) else {
                    operationError = .saveFailed
                    return false
                }
                let updated = try CallAction(
                    id: existing.id,
                    boardID: existing.boardID,
                    title: draft.title,
                    speechText: draft.speechText,
                    type: existing.type,
                    voiceTemplateID: existing.voiceTemplateID,
                    sortOrder: existing.sortOrder,
                    style: draft.style,
                    playbackMode: draft.playbackMode,
                    audioFileName: resolvedAudioFileName(draft),
                    promptToneEnabled: existing.promptToneEnabled,
                    storesInRecentCalls: existing.storesInRecentCalls,
                    isEnabled: draft.isEnabled,
                    createdAt: existing.createdAt,
                    updatedAt: max(now, existing.createdAt)
                )
                try await actions.save(updated)
                // Free a clip that the edit replaced or removed.
                if let previous = existing.audioFileName, previous != updated.audioFileName {
                    audioClips.removeClip(named: previous)
                }
            } else {
                let nextSortOrder = content.actions.map(\.sortOrder).max().map { $0 + 1 } ?? 0
                let created = try CallAction(
                    boardID: boardID,
                    title: draft.title,
                    speechText: draft.speechText,
                    sortOrder: nextSortOrder,
                    style: draft.style,
                    playbackMode: draft.playbackMode,
                    audioFileName: resolvedAudioFileName(draft),
                    isEnabled: draft.isEnabled,
                    now: now
                )
                try await actions.save(created)
            }
            await reloadContent()
            return true
        } catch {
            operationError = .saveFailed
            return false
        }
    }

    @discardableResult
    func createActions(batch: BatchDraft) async -> Bool {
        guard case .loaded(let content) = state else {
            operationError = .saveFailed
            return false
        }
        guard batch.count > 0, batch.startNumber >= 0 else {
            operationError = .saveFailed
            return false
        }

        do {
            let now = Date()
            var nextSortOrder = content.actions.map(\.sortOrder).max().map { $0 + 1 } ?? 0
            var newActions: [CallAction] = []
            for offset in 0..<batch.count {
                let name = batch.formattedTitle(for: batch.startNumber + offset)
                let resolvedAudio = resolveAudioForBatch(
                    mode: batch.playbackMode,
                    packID: batch.audioPackID,
                    title: name
                )
                let created = try CallAction(
                    boardID: boardID,
                    title: name,
                    speechText: batch.speechText(for: name),
                    sortOrder: nextSortOrder,
                    style: batch.style,
                    playbackMode: resolvedAudio == nil ? .text : .audio,
                    audioFileName: resolvedAudio,
                    isEnabled: batch.isEnabled,
                    now: now
                )
                newActions.append(created)
                nextSortOrder += 1
            }
            for action in newActions {
                try await actions.save(action)
            }
            await reloadContent()
            return true
        } catch {
            operationError = .saveFailed
            return false
        }
    }

    func setActionEnabled(_ isEnabled: Bool, actionID: UUID) async {
        guard let existing = loadedAction(id: actionID), existing.isEnabled != isEnabled else {
            return
        }

        do {
            var updated = existing
            updated.isEnabled = isEnabled
            updated.updatedAt = max(Date(), existing.createdAt)
            try await actions.save(updated)
            await reloadContent()
        } catch {
            operationError = .saveFailed
        }
    }

    func deleteAction(id: UUID) async {
        let clipName = loadedAction(id: id)?.audioFileName
        do {
            try await actions.delete(id: id)
            if let clipName {
                audioClips.removeClip(named: clipName)
            }
            await reloadContent()
        } catch {
            operationError = .deleteFailed
        }
    }

    func deleteActions(at offsets: IndexSet) async {
        guard case .loaded(let content) = state else {
            return
        }
        for offset in offsets where content.actions.indices.contains(offset) {
            await deleteAction(id: content.actions[offset].id)
            if operationError != nil {
                return
            }
        }
    }

    /// Deletes every action whose id is in `ids`. Stops on the first error
    /// so the user sees a single failure alert rather than one per row.
    func deleteActions(ids: [UUID]) async {
        for id in ids {
            await deleteAction(id: id)
            if operationError != nil {
                return
            }
        }
    }

    func moveActions(from offsets: IndexSet, to destination: Int) async {
        guard case .loaded(let content) = state else {
            return
        }

        var orderedActions = content.actions
        orderedActions.applyMove(fromOffsets: offsets, toOffset: destination)

        do {
            try await actions.reorder(
                boardID: boardID,
                orderedIDs: orderedActions.map(\.id)
            )
        } catch {
            operationError = .reorderFailed
        }
        await reloadContent()
    }

    private func reloadContent() async {
        do {
            guard let board = try await boards.board(id: boardID) else {
                state = .empty
                return
            }
            let boardActions = try await actions.fetch(
                boardID: boardID,
                includeDisabled: true
            )
            state = .loaded(Content(board: board, actions: boardActions))
        } catch {
            state = .failed
        }
    }

    private func loadedAction(id: UUID) -> CallAction? {
        guard case .loaded(let content) = state else {
            return nil
        }
        return content.actions.first { $0.id == id }
    }

    /// The clip reference to persist: only meaningful for audio playback, so
    /// switching back to text drops any stored name.
    private func resolvedAudioFileName(_ draft: ActionDraft) -> String? {
        draft.playbackMode == .audio ? draft.audioFileName : nil
    }

    /// Resolves the audio file for a single batch-generated action.
    ///
    /// - `.text`  → always `nil` (caller uses speech text).
    /// - `.audio` → tries the title's trailing number against the selected
    ///   source: an imported pack when one is picked, otherwise the bundled
    ///   pool. When no clip matches, the action degrades to `.text` so the
    ///   batch still completes. Users can then pick a clip manually from the
    ///   action editor.
    private func resolveAudioForBatch(
        mode: CallActionPlaybackMode,
        packID: UUID?,
        title: String
    ) -> String? {
        guard mode == .audio else {
            return nil
        }
        // Title's trailing digits — keeps `A01 → 01.mp3` predictable.
        guard let match = title.range(of: #"\d+$"#, options: .regularExpression),
              let number = Int(title[match]) else {
            return nil
        }
        if let packID {
            return resolvePackClip(packID: packID, number: number)
        }
        let padded = String(format: "%02d", number)
        let candidate = "\(padded).mp3"
        return BundledAudioClipCatalog.contains(clipNamed: candidate) ? candidate : nil
    }

    /// Finds the pack clip whose file-name number matches, addressed as
    /// "<packUUID>/<fileName>" so the composite store can resolve it.
    private func resolvePackClip(packID: UUID, number: Int) -> String? {
        guard let pack = audioPacks.listPacks().first(where: { $0.id == packID }),
              let fileName = pack.clipFileNames.first(where: { clipNumber(in: $0) == number }) else {
            return nil
        }
        return "\(packID.uuidString)/\(fileName)"
    }

    /// The trailing number of a clip's file stem ("01.mp3" → 1,
    /// "A12.wav" → 12), or `nil` when the name carries no number.
    private func clipNumber(in fileName: String) -> Int? {
        let stem = (fileName as NSString).deletingPathExtension
        guard let match = stem.range(of: #"\d+$"#, options: .regularExpression) else {
            return nil
        }
        return Int(stem[match])
    }
}
