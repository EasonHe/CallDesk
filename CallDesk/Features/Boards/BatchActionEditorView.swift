import SwiftUI

struct BatchActionEditorView: View {
    let audioPacks: [AudioPack]
    let onSave: (BoardDetailViewModel.BatchDraft) async -> Bool

    @State private var draft = BoardDetailViewModel.BatchDraft()
    @State private var countText: String = "10"
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    /// The largest batch the user can create. Audio mode is limited by the
    /// number of clips in the selected audio source; text mode can generate
    /// far more since each action just speaks its own text.
    private var maxCount: Int {
        if draft.playbackMode == .audio {
            return max(audioClipCount, 1)
        }
        return 999
    }

    /// Clips available from the picked audio source: the selected imported
    /// pack, or the built-in catalog when none is picked.
    private var audioClipCount: Int {
        if let packID = draft.audioPackID,
           let pack = audioPacks.first(where: { $0.id == packID }) {
            return pack.clipFileNames.count
        }
        return BundledAudioClipCatalog.allClipFileNames.count
    }

    init(audioPacks: [AudioPack] = [], onSave: @escaping (BoardDetailViewModel.BatchDraft) async -> Bool) {
        self.audioPacks = audioPacks
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("前缀", text: $draft.prefix)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                } header: {
                    Text("前缀")
                } footer: {
                    Text("可选。例如 A、B 或 C。")
                }

                Section {
                    HStack {
                        TextField("数量", text: $countText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .onSubmit { commitCountText() }
                            .onChange(of: countText) { _ in commitCountText() }

                        Stepper(
                            "",
                            value: countBinding,
                            in: 1...maxCount
                        )
                        .labelsHidden()
                    }
                    Stepper(value: $draft.startNumber, in: 0...9999) {
                        LabeledContent("起始号码", value: "\(draft.startNumber)")
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if draft.playbackMode == .audio {
                            Text("上限：\(maxCount)（音频总数）。")
                        }
                        previewFooter
                    }
                }

                Section {
                    Picker("播放方式", selection: $draft.playbackMode) {
                        ForEach(CallActionPlaybackMode.allCases, id: \.self) { mode in
                            Text(mode.localizedTitle)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(draft.playbackMode == .audio
                        ? audioSourceFooter
                        : "每个叫号项播报其生成的名称。")
                }

                if draft.playbackMode == .audio, !audioPacks.isEmpty {
                    Section {
                        Picker("音频来源", selection: $draft.audioPackID) {
                            Text("内置音频").tag(UUID?.none)
                            ForEach(audioPacks) { pack in
                                Text(pack.name).tag(UUID?.some(pack.id))
                            }
                        }
                    } footer: {
                        Text("按号码匹配音频：叫号 A01 使用编号为 1 的音频。")
                    }
                }

                if draft.playbackMode == .text {
                    Section {
                        TextField("播报文本", text: $draft.speechTemplate, axis: .vertical)
                            .lineLimit(2...5)
                    } header: {
                        Text("播报文本")
                    } footer: {
                        Text("预填默认播报内容。用 {name} 或 {number} 表示生成的名称，留空则直接播报名称本身。半角标点会自动转换。")
                    }
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
            .navigationTitle("批量添加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        save()
                    }
                    .disabled(isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    /// Footer explaining how clips get assigned in audio mode.
    private var audioSourceFooter: String {
        draft.audioPackID == nil
            ? "将按顺序分配内置音频。"
            : "将按顺序分配所选音频包中的音频。"
    }

    @ViewBuilder
    private var previewFooter: some View {
        if draft.count > 0 {
            let first = draft.formattedTitle(for: draft.startNumber)
            if draft.count == 1 {
                Text(verbatim: first)
            } else {
                let last = draft.formattedTitle(for: draft.startNumber + draft.count - 1)
                Text(verbatim: "\(first) … \(last)")
            }
        }
    }

    /// A binding that keeps `draft.count` in sync with the text field. The
    /// setter writes the integer back to the text representation so the
    /// stepper and the field always agree.
    private var countBinding: Binding<Int> {
        Binding(
            get: { draft.count },
            set: { newValue in
                draft.count = newValue
                countText = "\(newValue)"
            }
        )
    }

    /// Parses the text field input, clamps it to the valid range, and
    /// writes the sanitized value back to both the draft and the text.
    /// Invalid input falls back to the previous draft value.
    private func commitCountText() {
        let trimmed = countText.trimmingCharacters(in: .whitespaces)
        guard let parsed = Int(trimmed), parsed > 0 else {
            countText = "\(draft.count)"
            return
        }
        let clamped = min(max(parsed, 1), maxCount)
        draft.count = clamped
        countText = "\(clamped)"
    }

    private func save() {
        commitCountText()
        isSaving = true
        Task {
            if await onSave(draft) {
                dismiss()
            }
            isSaving = false
        }
    }
}

#Preview {
    BatchActionEditorView(audioPacks: []) { _ in
        true
    }
}
