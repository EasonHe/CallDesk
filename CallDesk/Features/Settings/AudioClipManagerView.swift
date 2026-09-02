import SwiftUI
import UniformTypeIdentifiers

struct AudioClipManagerView: View {
    @StateObject private var viewModel: AudioClipManagerViewModel
    @State private var isSingleImporterPresented = false
    @State private var isPackImporterPresented = false
    @State private var pendingPackURL: URL?
    @State private var newPackName: String = ""
    @State private var showingPackNameDialog = false

    init(viewModel: AudioClipManagerViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        content
            .navigationTitle("音频素材")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            isPackImporterPresented = true
                        } label: {
                            Label("导入音频包（zip）", systemImage: "archivebox")
                        }
                        Button {
                            isSingleImporterPresented = true
                        } label: {
                            Label("导入单个音频", systemImage: "plus")
                        }
                    } label: {
                        Label("导入", systemImage: "plus")
                    }
                }
            }
            .alert(
                "操作失败",
                isPresented: operationErrorBinding,
                presenting: viewModel.operationError
            ) { _ in
                Button("好", role: .cancel) {}
            } message: { error in
                Text(message(for: error))
            }
            .fileImporter(
                isPresented: $isSingleImporterPresented,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                handleSingleImport(result)
            }
            .fileImporter(
                isPresented: $isPackImporterPresented,
                allowedContentTypes: [.zip],
                allowsMultipleSelection: false
            ) { result in
                handlePackPick(result)
            }
            .alert("音频包名称", isPresented: $showingPackNameDialog) {
                TextField("名称", text: $newPackName)
                    .autocorrectionDisabled()
                Button("取消", role: .cancel) {
                    pendingPackURL = nil
                    newPackName = ""
                }
                Button("导入") {
                    commitPackImport()
                }
                .disabled(newPackName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text("为此音频包命名，名称必须唯一。")
            }
            .task {
                viewModel.load()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            FeatureEmptyStateView(
                systemImage: "waveform",
                title: "暂无音频素材",
                message: "导入 zip 音频包或添加单个音频文件。"
            )
        case .loaded(let loadedContent):
            clipList(loadedContent)
        case .failed:
            FeatureErrorStateView {
                viewModel.load()
            }
        }
    }

    private func clipList(_ content: AudioClipManagerViewModel.Content) -> some View {
        List {
            Section {
                LabeledContent("内置音频", value: "\(content.bundledCount)")
            } footer: {
                Text("内置音频随 App 附带，不可删除。")
            }

            if !content.packs.isEmpty {
                Section("音频包") {
                    ForEach(content.packs) { pack in
                        NavigationLink {
                            AudioPackDetailView(
                                pack: pack,
                                viewModel: viewModel
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pack.name)
                                    .font(.body.weight(.semibold))
                                Text(verbatim: String(
                                    format: NSLocalizedString("%d 个音频", comment: ""),
                                    pack.clipFileNames.count
                                ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        viewModel.deletePacks(at: offsets)
                    }
                }
            }

            if !content.userClipNames.isEmpty {
                Section("单个音频") {
                    ForEach(content.userClipNames, id: \.self) { name in
                        Text(verbatim: name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .onDelete { offsets in
                        viewModel.deleteClips(at: offsets)
                    }
                }
            }
        }
    }

    private func handleSingleImport(_ result: Result<[URL], any Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else {
            return
        }
        for url in urls {
            _ = viewModel.importClip(from: url)
        }
    }

    /// The file importer returned a zip URL. Stash it and ask the user for
    /// a pack name before actually importing — importing is deferred until
    /// the user confirms the name dialog.
    private func handlePackPick(_ result: Result<[URL], any Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            return
        }
        pendingPackURL = url
        newPackName = url.deletingPathExtension().lastPathComponent
        showingPackNameDialog = true
    }

    private func commitPackImport() {
        guard let url = pendingPackURL else {
            showingPackNameDialog = false
            return
        }
        let trimmed = newPackName.trimmingCharacters(in: .whitespacesAndNewlines)
        showingPackNameDialog = false
        guard !trimmed.isEmpty else {
            pendingPackURL = nil
            newPackName = ""
            return
        }
        _ = viewModel.importPack(from: url, named: trimmed)
        pendingPackURL = nil
        newPackName = ""
    }

    private var operationErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.operationError != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.operationError = nil
                }
            }
        )
    }

    private func message(for error: AudioClipManagerViewModel.OperationError?) -> LocalizedStringKey {
        switch error {
        case .importFailed:
            return "音频文件无法导入。"
        case .packImportFailed:
            return "zip 压缩包无法导入。"
        case .duplicatePackName:
            return "已存在同名音频包。"
        case .deleteFailed:
            return "音频文件无法删除。"
        case .none:
            return ""
        }
    }
}

/// Lists the clips inside a single pack. The whole pack can be deleted from
/// the toolbar; individual clips are read-only because they belong to the
/// pack archive.
struct AudioPackDetailView: View {
    let pack: AudioPack
    @ObservedObject var viewModel: AudioClipManagerViewModel

    var body: some View {
        List {
            Section {
                LabeledContent("音频数", value: "\(pack.clipFileNames.count)")
                LabeledContent("创建时间", value: pack.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
            Section("文件") {
                ForEach(pack.clipFileNames, id: \.self) { name in
                    Text(verbatim: name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .navigationTitle(pack.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    viewModel.deletePack(id: pack.id)
                } label: {
                    Label("删除音频包", systemImage: "trash")
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AudioClipManagerView(
            viewModel: AudioClipManagerViewModel(
                audioClips: FileSystemAudioClipStore(),
                audioPacks: FileSystemAudioPackStore()
            )
        )
    }
}
