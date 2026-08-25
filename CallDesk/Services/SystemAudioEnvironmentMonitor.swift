import Combine
import Foundation

#if canImport(AVFAudio)
import AVFAudio

/// Mirrors the live `AVAudioSession` state.
///
/// The monitor keeps the current output route up to date across route
/// changes (headphones plugged or unplugged, Bluetooth and AirPlay
/// devices connecting) and republishes interruptions such as incoming
/// phone calls. It never mutates the session itself; activation stays
/// with `SystemAudioSessionManager` around each utterance, which is also
/// what recovers the session after an interruption or a media services
/// reset.
@MainActor
final class SystemAudioEnvironmentMonitor: AudioEnvironmentMonitoring {
    private let routeSubject: CurrentValueSubject<AudioRouteDescription, Never>
    private let interruptionSubject = PassthroughSubject<AudioInterruptionEvent, Never>()
    private let readRoute: () -> AudioRouteDescription
    private var subscriptions: Set<AnyCancellable> = []

    /// - Parameters:
    ///   - notificationCenter: The center delivering the audio session
    ///     notifications; injectable for tests.
    ///   - readRoute: Reads the route to publish; defaults to the shared
    ///     audio session and is injectable for tests.
    init(
        notificationCenter: NotificationCenter = .default,
        readRoute: @escaping () -> AudioRouteDescription = SystemAudioEnvironmentMonitor.systemRoute
    ) {
        self.readRoute = readRoute
        routeSubject = CurrentValueSubject(readRoute())

        notificationCenter.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshRoute()
            }
            .store(in: &subscriptions)

        // After a media services reset the route must be re-read as well;
        // the session itself is reconfigured on the next activation.
        notificationCenter.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshRoute()
            }
            .store(in: &subscriptions)

        notificationCenter.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleInterruption(notification)
            }
            .store(in: &subscriptions)
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

    private func refreshRoute() {
        let route = readRoute()
        if route != routeSubject.value {
            routeSubject.send(route)
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else {
            return
        }

        switch type {
        case .began:
            interruptionSubject.send(.began)
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions ?? 0)
            interruptionSubject.send(.ended(shouldResume: options.contains(.shouldResume)))
        @unknown default:
            break
        }
    }

    // MARK: - Route mapping

    /// Reads the first output of the shared audio session.
    nonisolated static func systemRoute() -> AudioRouteDescription {
        route(for: AVAudioSession.sharedInstance().currentRoute)
    }

    nonisolated static func route(
        for routeDescription: AVAudioSessionRouteDescription
    ) -> AudioRouteDescription {
        guard let output = routeDescription.outputs.first else {
            return .defaultSpeaker
        }
        let type = routeType(for: output.portType)
        return (try? AudioRouteDescription(type: type, name: output.portName)) ?? .unknown
    }

    nonisolated static func routeType(for port: AVAudioSession.Port) -> AudioRouteType {
        switch port {
        case .builtInSpeaker:
            return .builtInSpeaker
        case .builtInReceiver:
            return .receiver
        case .headphones:
            return .headphones
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
            return .bluetooth
        case .airPlay:
            return .airPlay
        case .usbAudio, .lineOut, .HDMI:
            return .wired
        default:
            return .unknown
        }
    }
}
#endif
