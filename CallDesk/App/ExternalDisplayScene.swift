import SwiftUI

#if canImport(UIKit)
import UIKit

/// Routes newly connecting scenes: the external display role gets the
/// signage scene, every other role stays with the SwiftUI lifecycle.
///
/// SwiftUI has no scene type for external displays on iOS, so this is
/// the sanctioned UIKit boundary for the second screen.
final class CallDeskAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        if connectingSceneSession.role == .windowExternalDisplayNonInteractive {
            configuration.delegateClass = ExternalDisplaySceneDelegate.self
        }
        return configuration
    }
}

/// Hosts `ExternalDisplayView` in a window on the external screen.
final class ExternalDisplaySceneDelegate: NSObject, UIWindowSceneDelegate {
    /// UIKit instantiates this delegate itself, so the presenter is
    /// handed over through this single hook, set once at launch.
    static var presenter: ExternalDisplayPresenter?

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard
            let windowScene = scene as? UIWindowScene,
            let presenter = Self.presenter
        else {
            return
        }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(
            rootView: ExternalDisplayView(presenter: presenter)
        )
        window.isHidden = false
        self.window = window
        presenter.displayDidConnect()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        Self.presenter?.displayDidDisconnect()
        window = nil
    }
}
#endif
