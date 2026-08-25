import Combine
import Foundation

/// Observes whether an external (second) display is connected.
///
/// The Settings screen shows this state; the presentation itself is
/// owned by `ExternalDisplayPresenter` and the external scene delegate.
@MainActor
protocol ExternalDisplayMonitoring: AnyObject {
    /// Whether an external display is showing the call presentation.
    var isConnected: Bool { get }

    /// Emits every connection change, including the current value.
    var isConnectedPublisher: AnyPublisher<Bool, Never> { get }
}

/// A monitor with a manually controlled connection state, used by
/// previews and tests where no real external display is involved.
@MainActor
final class FixedExternalDisplayMonitor: ExternalDisplayMonitoring {
    private let connectionSubject: CurrentValueSubject<Bool, Never>

    init(isConnected: Bool = false) {
        connectionSubject = CurrentValueSubject(isConnected)
    }

    var isConnected: Bool {
        connectionSubject.value
    }

    var isConnectedPublisher: AnyPublisher<Bool, Never> {
        connectionSubject.eraseToAnyPublisher()
    }

    func setConnected(_ isConnected: Bool) {
        connectionSubject.send(isConnected)
    }
}
