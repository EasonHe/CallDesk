import SwiftUI

/// A soft, continuously "breathing" stroke that marks the currently
/// speaking tile. The border and its glow gently fade in and out in a
/// loop. With Reduce Motion enabled it settles on a calm static highlight
/// so the active tile stays identifiable without the pulsing.
struct BreathingBorder: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let cornerRadius: CGFloat
    var color: Color = .indigo

    @State private var breathing = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(color.opacity(strokeOpacity), lineWidth: 2.5)
            .shadow(color: color.opacity(0.5), radius: 10)
            .opacity(strokeOpacity)
            .allowsHitTesting(false)
            .onAppear(perform: startBreathing)
    }

    private var strokeOpacity: Double {
        reduceMotion ? 0.9 : (breathing ? 1 : 0.35)
    }

    private func startBreathing() {
        guard !reduceMotion else {
            return
        }
        withAnimation(
            Animation.easeInOut(duration: 1.3).repeatForever(autoreverses: true)
        ) {
            breathing = true
        }
    }
}
