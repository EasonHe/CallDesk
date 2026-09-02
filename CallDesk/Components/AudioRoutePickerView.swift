import SwiftUI

#if canImport(AVKit)
import AVKit

/// The system output picker for Bluetooth, AirPlay, and other routes.
///
/// SwiftUI has no native route picker, so this wraps `AVRoutePickerView`;
/// the sheet it presents is owned entirely by the system.
struct AudioRoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        AVRoutePickerView()
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif
