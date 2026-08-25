import SwiftUI

struct FeatureErrorStateView: View {
    let retryAction: () -> Void

    var body: some View {
        VStack(spacing: CallDeskTheme.pageSpacing) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("无法加载")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text("加载此内容时出现了问题。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("重试", action: retryAction)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    FeatureErrorStateView(retryAction: {})
}
