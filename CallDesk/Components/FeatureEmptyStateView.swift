import SwiftUI

struct FeatureEmptyStateView: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: CallDeskTheme.pageSpacing) {
                    Image(systemName: systemImage)
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Text(title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .accessibilityElement(children: .combine)
                .padding()
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    FeatureEmptyStateView(
        systemImage: "speaker.wave.2.fill",
        title: "No Calling Content",
        message: "Calling blocks will appear here when they are available."
    )
}
