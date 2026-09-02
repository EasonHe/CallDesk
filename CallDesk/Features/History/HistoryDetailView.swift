import SwiftUI

/// Shows one history record from its stored snapshot.
///
/// Every field comes from the record itself, so the details keep working
/// after the original action, board, or scene has been deleted.
struct HistoryDetailView: View {
    let record: CallRecord
    @ObservedObject var viewModel: HistoryViewModel
    /// Records of archived boards stay view-only: recall and deletion
    /// actions are hidden together with the board's other mutations.
    var isReadOnly = false

    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDeletion = false

    var body: some View {
        List {
            Section {
                LabeledContent("结果") {
                    Text(record.result.displayName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(record.result.displayTint.color.opacity(0.15))
                        )
                        .foregroundStyle(record.result.displayTint.color)
                }

                LabeledContent("播报文本") {
                    Text(record.spokenTextSnapshot)
                        .multilineTextAlignment(.trailing)
                }

                LabeledContent("开始时间") {
                    Text(record.startedAt, format: .dateTime.year().month().day().hour().minute().second())
                }

                if let completedAt = record.completedAt {
                    LabeledContent("完成时间") {
                        Text(completedAt, format: .dateTime.year().month().day().hour().minute().second())
                    }
                }

                LabeledContent("重复次数") {
                    Text(record.repeatIndex, format: .number)
                }

                if let audioRouteName = record.audioRouteName {
                    LabeledContent("音频输出") {
                        Text(audioRouteName)
                    }
                }

                if let errorDescription = record.errorDescription {
                    LabeledContent("错误") {
                        Text(errorDescription)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } footer: {
                Text("历史记录是快照，原始叫号项删除后仍会保留。")
            }

            if !isReadOnly {
                Section {
                    Button("再次呼叫") {
                        Task {
                            await viewModel.recall(record)
                        }
                    }
                    .disabled(viewModel.isRecalling)

                    Button("删除", role: .destructive) {
                        isConfirmingDeletion = true
                    }
                }
            }
        }
        .navigationTitle(record.actionTitleSnapshot)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "删除这条历史记录？",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                Task {
                    await viewModel.deleteRecords(ids: [record.id])
                    dismiss()
                }
            }
        } message: {
            Text("此操作不可撤销。")
        }
    }
}
