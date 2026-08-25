import Combine
import Foundation

/// An audio session interruption reported by the system, such as an
/// incoming phone call or another app taking over the output.
enum AudioInterruptionEvent: Equatable {
    case began
    case ended(shouldResume: Bool)
}

/// Observes the device audio environment for the calling flow.
///
/// The playback category already follows the system output route, so
/// Bluetooth, AirPlay, and headphones work without extra routing code.
/// This abstraction mirrors that route for display and history recording
/// and republishes interruptions so the call service can end the affected
/// session in line with the audio session guidelines.
@MainActor
protocol AudioEnvironmentMonitoring: AnyObject {
    /// The output route announcements currently play through.
    var currentRoute: AudioRouteDescription { get }

    /// Emits every route change, including the current value.
    var routePublisher: AnyPublisher<AudioRouteDescription, Never> { get }

    /// Emits audio session interruptions while they happen.
    var interruptionPublisher: AnyPublisher<AudioInterruptionEvent, Never> { get }
}

/// A monitor with a manually controlled route, used by previews and tests
/// where no real audio hardware is involved.
@MainActor
final class FixedAudioEnvironmentMonitor: AudioEnvironmentMonitoring {
    private let routeSubject: CurrentValueSubject<AudioRouteDescription, Never>
    private let interruptionSubject = PassthroughSubject<AudioInterruptionEvent, Never>()

    init(route: AudioRouteDescription = .defaultSpeaker) {
        routeSubject = CurrentValueSubject(route)
    }

    var currentRoute: AudioRouteDescription {
        routeSubject.value
    }

    var routePublisher: AnyPublisher<AudioRouteDescription, Never> {
        routeSubject.eraseToAnyPublisher()
    }

    var interruptionPublisher: AnyPublisher<AudioInterruptionEvent, Never> {
        interruptionSubject.eraseToAnyPublisher()
    }

    func updateRoute(_ route: AudioRouteDescription) {
        routeSubject.send(route)
    }

    func reportInterruption(_ event: AudioInterruptionEvent) {
        interruptionSubject.send(event)
    }
}
