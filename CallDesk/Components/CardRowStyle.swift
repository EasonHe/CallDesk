import SwiftUI

/// Renders a `List` row as a rounded card with its own inset background,
/// matching the visual language used across the app.
struct CardRowStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(
                EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
            )
            .listRowSeparator(.hidden)
            .listRowBackground(
                RoundedRectangle(cornerRadius: CallDeskTheme.cardCornerRadius)
                    .fill(Color(.secondarySystemBackground))
            )
    }
}

extension View {
    func cardRowStyle() -> some View {
        modifier(CardRowStyle())
    }
}
