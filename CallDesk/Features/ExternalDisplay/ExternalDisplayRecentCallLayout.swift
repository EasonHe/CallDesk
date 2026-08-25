import CoreGraphics

/// Type and spacing values for the six recent-call cards on a distant display.
enum ExternalDisplayRecentCallLayout {
    static let numberFontSize: CGFloat = 104
    static let verticalPadding: CGFloat = 12
}

/// Calculates a readable grid for the recent-call cards shown on an external display.
nonisolated struct ExternalDisplayRecentCallGridLayout: Equatable {
    let columns: Int
    let rows: Int
    let cardSize: CGSize
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let numberFontSize: CGFloat
    let metadataFontSize: CGFloat

    static func make(in size: CGSize, itemCount: Int) -> Self {
        guard itemCount > 0, size.width > 0, size.height > 0 else {
            return Self(
                columns: 0,
                rows: 0,
                cardSize: .zero,
                horizontalSpacing: 0,
                verticalSpacing: 0,
                numberFontSize: 0,
                metadataFontSize: 0
            )
        }

        let columns = min(itemCount, 5)
        let rows = (itemCount + columns - 1) / columns
        let horizontalSpacing = min(25, max(10, size.width * 0.015))
        let verticalSpacing = rows == 1 ? 0 : min(16, max(8, size.height * 0.06))
        let cardWidth = (size.width - horizontalSpacing * CGFloat(columns - 1)) / CGFloat(columns)
        let cardHeight = (size.height - verticalSpacing * CGFloat(rows - 1)) / CGFloat(rows)
        let numberFontSize = min(104, max(44, min(cardWidth * 0.42, cardHeight * 0.58)))
        let metadataFontSize = min(20, max(12, numberFontSize * 0.20))

        return Self(
            columns: columns,
            rows: rows,
            cardSize: CGSize(width: cardWidth, height: cardHeight),
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing,
            numberFontSize: numberFontSize,
            metadataFontSize: metadataFontSize
        )
    }
}
