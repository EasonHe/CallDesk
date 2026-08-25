import SwiftUI

struct BoardEditorView: View {
    let title: LocalizedStringKey
    let onSave: (BoardsViewModel.BoardDraft) async -> Bool

    @State private var draft: BoardsViewModel.BoardDraft
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    init(
        title: LocalizedStringKey,
        draft: BoardsViewModel.BoardDraft,
        onSave: @escaping (BoardsViewModel.BoardDraft) async -> Bool
    ) {
        self.title = title
        self.onSave = onSave
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $draft.name)
                    TextField("副标题", text: $draft.subtitle)
                }

                Section {
                    Toggle("已归档", isOn: $draft.isArchived)
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
        }
    }

    private var canSave: Bool {
        !isSaving && !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

#Preview {
    BoardEditorView(
        title: "新建面板",
        draft: .init()
    ) { _ in
        true
    }
}
