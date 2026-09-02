import SwiftUI

/// A compact ring showing how much of the current board has been called.
///
/// The ring is purely derived from its fraction, so it never animates on
/// its own and stays calm under Reduce Motion; the progress simply updates
/// as tiles are called.
struct ProgressRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 4
    var tint: Color = .indigo

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.tertiarySystemFill), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }

    /// The ring fill for a board, clamped to the valid `0...1` range so an
    /// empty board never renders past the starting point.
    nonisolated static func fraction(calledCount: Int, totalCount: Int) -> Double {
        guard totalCount > 0 else {
            return 0
        }
        return min(1, max(0, Double(calledCount) / Double(totalCount)))
    }
}
