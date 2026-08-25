import Combine
import Foundation
import Testing
@testable import CallDesk

#if canImport(AVFAudio)
import AVFAudio

@MainActor
@Suite("System audio environment monitor")
struct SystemAudioEnvironmentMonitorTests {
    /// A mutable stand-in for the shared audio session route.
    @MainActor
    private final class RouteSource {
        var route: AudioRouteDescription = .defaultSpeaker
    }

    private func makeMonitor() -> (SystemAudioEnvironmentMonitor, NotificationCenter, RouteSource) {
        let notificationCenter = NotificationCenter()
        let source = RouteSource()
        let monitor = SystemAudioEnvironmentMonitor(
            notificationCenter: notificationCenter,
            readRoute: { MainActor.assumeIsolated { source.route } }
        )
        return (monitor, notificationCenter, source)
    }

    private func waitUntil(
        _ description: String,
        condition: () -> Bool
    ) async {
        for _ in 0..<500 {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        Issue.record("Timed out waiting until \(description)")
    }

    // MARK: - Route mapping

    @Test("Ports map onto the matching route types")
    func portsMapOntoMatchingRouteTypes() {
        #expect(SystemAudioEnvironmentMonitor.routeType(for: .builtInSpeaker) == .builtInSpeaker)
        #expect(SystemAudioEnvironmentMonitor.routeType(for: .builtInReceiver) == .receiver)
        #expect(SystemAudioEnvironmentMonitor.routeType(for: .headphones) == .headphones)
        #expect(SystemAudioEnvironmentMonitor.routeType(for: .bluetoothA2DP) == .bluetooth)
        #expect(SystemAudioEnvironmentMonitor.routeType(for: .bluetoothLE) == .bluetooth)
        #expect(SystemAudioEnvironmentMonitor.routeType(for: .bluetoothHFP) == .bluetooth)
        #expect(SystemAudioEnvironmentMonitor.routeType(for: .airPlay) == .airPlay)
        #expect(SystemAudioEnvironmentMonitor.routeType(for: .usbAudio) == .wired)
        #expect(SystemAudioEnvironmentMonitor.routeType(for: .lineOut) == .wired)
        #expect(SystemAudioEnvironmentMonitor.routeType(for: .HDMI) == .wired)
        #expect(SystemAudioEnvironmentMonitor.routeType(for: .builtInMic) == .unknown)
    }

    // MARK: - Route changes

    @Test("The initial route is read on creation")
    func initialRouteIsReadOnCreation() {
        let (monitor, _, _) = makeMonitor()

        #expect(monitor.currentRoute == .defaultSpeaker)
    }

    @Test("A route change notification publishes the new route")
    func routeChangeNotificationPublishesNewRoute() async throws {
        let (monitor, notificationCenter, source) = makeMonitor()
        let headphones = try AudioRouteDescription(type: .headphones, name: "Headphones")

        source.route = headphones
        notificationCenter.post(name: AVAudioSession.routeChangeNotification, object: nil)

        await waitUntil("the route reflects the headphones") {
            monitor.currentRoute == headphones
        }
    }

    @Test("An unchanged route is not republished")
    func unchangedRouteIsNotRepublished() async {
        let (monitor, notificationCenter, _) = makeMonitor()
        var received: [AudioRouteDescription] = []
        let subscription = monitor.routePublisher.sink { received.append($0) }
        defer { subscription.cancel() }

        notificationCenter.post(name: AVAudioSession.routeChangeNotification, object: nil)
        // Let the main queue drain the notification delivery.
        for _ in 0..<5 {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }

        #expect(received == [.defaultSpeaker])
    }

    @Test("A media services reset refreshes the route")
    func mediaServicesResetRefreshesRoute() async throws {
        let (monitor, notificationCenter, source) = makeMonitor()
        let bluetooth = try AudioRouteDescription(type: .bluetooth, name: "Counter Speaker")

        source.route = bluetooth
        notificationCenter.post(
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )

        await waitUntil("the route reflects the Bluetooth speaker") {
            monitor.currentRoute == bluetooth
        }
    }

    // MARK: - Interruptions

    @Test("An interruption start is republished as began")
    func interruptionStartIsRepublishedAsBegan() async {
        let (monitor, notificationCenter, _) = makeMonitor()
        var received: [AudioInterruptionEvent] = []
        let subscription = monitor.interruptionPublisher.sink { received.append($0) }
        defer { subscription.cancel() }

        notificationCenter.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
            ]
        )

        await waitUntil("the began event arrives") {
            received == [.began]
        }
    }

    @Test("An interruption end carries the resume hint")
    func interruptionEndCarriesResumeHint() async {
        let (monitor, notificationCenter, _) = makeMonitor()
        var received: [AudioInterruptionEvent] = []
        let subscription = monitor.interruptionPublisher.sink { received.append($0) }
        defer { subscription.cancel() }

        notificationCenter.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                AVAudioSessionInterruptionOptionKey:
                    AVAudioSession.InterruptionOptions.shouldResume.rawValue
            ]
        )
        notificationCenter.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue
            ]
        )

        await waitUntil("both ended events arrive") {
            received == [.ended(shouldResume: true), .ended(shouldResume: false)]
        }
    }

    @Test("An interruption without type information is ignored")
    func interruptionWithoutTypeInformationIsIgnored() async {
        let (monitor, notificationCenter, _) = makeMonitor()
        var received: [AudioInterruptionEvent] = []
        let subscription = monitor.interruptionPublisher.sink { received.append($0) }
        defer { subscription.cancel() }

        notificationCenter.post(name: AVAudioSession.interruptionNotification, object: nil)
        for _ in 0..<5 {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }

        #expect(received.isEmpty)
    }
}
#endif
