import UIKit

/// iPad mini (6th generation) does not include a Taptic Engine, so a
/// `UIImpactFeedbackGenerator` cannot produce a physical tap on it.
@MainActor
enum HapticFeedbackSupport {
    static var isAvailable: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
}
