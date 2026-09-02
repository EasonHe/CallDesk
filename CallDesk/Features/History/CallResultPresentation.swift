import SwiftUI

/// The semantic accent for a history result badge, kept separate from the
/// concrete color so the mapping stays testable and view-agnostic.
nonisolated enum CallResultTint: String, CaseIterable, Sendable {
    case neutral
    case success
    case cancelled
    case interrupted
    case failure

    var color: Color {
        switch self {
        case .neutral:
            .gray
        case .success:
            .green
        case .cancelled:
            .orange
        case .interrupted:
            .yellow
        case .failure:
            .red
        }
    }
}

extension CallResult {
    /// The badge tint reflecting what happened to the call.
    var displayTint: CallResultTint {
        switch self {
        case .queued:
            .neutral
        case .completed:
            .success
        case .cancelled:
            .cancelled
        case .interrupted:
            .interrupted
        case .failed:
            .failure
        }
    }
}
