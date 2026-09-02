import SwiftUI
import UniformTypeIdentifiers

struct ActionEditorView: View {
    let title: LocalizedStringKey
    let onImportAudio: (URL) -> String?
    let onSave: (BoardDetailViewModel.ActionDraft) async -> Bool

    @State private var draft: BoardDetailViewModel.ActionDraft
    @State private var isSaving = false
    @State private var isAudioImporterPresented = false
    @Environment(\.dismiss) private var dismiss

    init(
        title: LocalizedStringKey,
        draft: BoardDetailViewModel.ActionDraft,
        onImportAudio: @escaping (URL) -> String? = { _ in nil },
        onSave: @escaping (BoardDetailViewModel.ActionDraft) async -> Bool
    ) {
        self.title = title
        self.onImportAudio = onImportAudio
        self.onSave = onSave
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("标题", text: $draft.title)
                }

                Section {
                    Picker("播放方式", selection: $draft.playbackMode) {
                        ForEach(CallActionPlaybackMode.allCases, id: \.self) { mode in
                            Text(mode.localizedTitle)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                switch draft.playbackMode {
                case .text:
                    Section {
                        TextField("播报文本", text: $draft.speechText, axis: .vertical)
                            .lineLimit(2...5)
                    }
                case .audio:
                    audioSection
                }

                Section {
                    Picker("样式", selection: $draft.style) {
                        ForEach(CallActionStyle.allCases, id: \.self) { style in
                            Text(style.localizedTitle)
                                .tag(style)
                        }
                    }
                    Toggle("启用", isOn: $draft.isEnabled)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .fileImporter(
                isPresented: $isAudioImporterPresented,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                handleAudioImport(result)
            }
        }
    }

    @ViewBuilder
    private var audioSection: some View {
        Section {
            if !bundledClipNames.isEmpty {
                Picker("默认音频", selection: bundledSelection) {
                    Text("无").tag(String?.none)
                    ForEach(bundledClipNames, id: \.self) { name in
                        Text(displayName(forBundled: name)).tag(String?.some(name))
                    }
                }
            }

            Button {
                isAudioImporterPresented = true
            } label: {
                Label(
                    draft.audioFileName == nil ? "选择音频" : "更换音频",
                    systemImage: "waveform"
                )
            }

            if let audioFileName = draft.audioFileName {
                LabeledContent("音频") {
                    Text(verbatim: displayName(forStored: audioFileName))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        } footer: {
            Text("导入自定义音频以替代文本播报。")
        }
    }

    private var bundledClipNames: [String] {
        BundledAudioClipCatalog.allClipFileNames
    }

    /// The picker binding: selecting a bundled clip assigns its name to the
    /// draft; choosing "None" clears the selection.
    private var bundledSelection: Binding<String?> {
        Binding(
            get: {
                guard let name = draft.audioFileName,
                      BundledAudioClipCatalog.contains(clipNamed: name) else {
                    return nil
                }
                return name
            },
            set: { newName in
                draft.audioFileName = newName
            }
        )
    }

    private func displayName(forBundled name: String) -> String {
        String(name.split(separator: ".").first ?? Substring(name))
    }

    private func displayName(forStored name: String) -> String {
        if BundledAudioClipCatalog.contains(clipNamed: name) {
            return displayName(forBundled: name)
        }
        return name
    }

    private var canSave: Bool {
        guard !isSaving else {
            return false
        }
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return false
        }
        switch draft.playbackMode {
        case .text:
            return !draft.speechText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .audio:
            return draft.audioFileName != nil
        }
    }

    private func handleAudioImport(_ result: Result<[URL], any Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            return
        }
        if let storedName = onImportAudio(url) {
            draft.audioFileName = storedName
        }
    }

    private func save() {
        isSaving = true
        Task {
            if await onSave(draft) {
                dismiss()
            }
            isSaving = false
        }
    }
}

extension CallActionStyle {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .standard:
            return "标准"
        case .accent:
            return "强调"
        case .success:
            return "成功"
        case .warning:
            return "警告"
        case .critical:
            return "紧急"
        case .neutral:
            return "中性"
        }
    }
}

extension CallActionPlaybackMode {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .text:
            return "播报文本"
        case .audio:
            return "播放音频"
        }
    }
}

#Preview {
    ActionEditorView(
        title: "新建叫号项",
        draft: .init()
    ) { _ in
        true
    }
}
