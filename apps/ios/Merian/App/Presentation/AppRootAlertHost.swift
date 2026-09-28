import SwiftUI
import UIKit

/// One root alert host, including while Capture's root sheet is open. SwiftUI's
/// root `.alert` attempts to present underneath that sheet and can drop the alert.
/// Actions remain injected; this bridge never changes navigation or persistence.
struct AppRootAlertHost: ViewModifier {
    let request: AppRootAlert?
    let openAppleInstructions: () -> Void
    let resolveAppleRevocation: () -> Void
    let updateApp: () -> Void
    let dismissUpdate: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.background {
            AppRootAlertBridge(
                request: request, isActive: scenePhase == .active,
                openAppleInstructions: openAppleInstructions,
                resolveAppleRevocation: resolveAppleRevocation,
                updateApp: updateApp, dismissUpdate: dismissUpdate
            )
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }
}

private struct AppRootAlertBridge: UIViewControllerRepresentable {
    let request: AppRootAlert?
    let isActive: Bool
    let openAppleInstructions: () -> Void
    let resolveAppleRevocation: () -> Void
    let updateApp: () -> Void
    let dismissUpdate: () -> Void

    func makeUIViewController(context: Context) -> AppRootAlertController {
        AppRootAlertController()
    }

    func updateUIViewController(_ controller: AppRootAlertController, context: Context) {
        controller.configure(self)
    }

    static func dismantleUIViewController(_ controller: AppRootAlertController, coordinator: ()) {
        controller.stop()
    }
}

@MainActor
private final class AppRootAlertController: UIViewController {
    private var configuration: AppRootAlertBridge?
    private weak var ownedAlert: UIAlertController?
    private var presentedRequest: AppRootAlert?
    private var consumedRequest: AppRootAlert?
    private var presentationTask: Task<Void, Never>?

    func configure(_ configuration: AppRootAlertBridge) {
        if self.configuration?.request != configuration.request {
            consumedRequest = nil
        }
        self.configuration = configuration
        presentationTask?.cancel()
        // Yield out of SwiftUI's update transaction before presenting UIKit UI.
        presentationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let configuration = self.configuration else { return }
                if let alert = self.ownedAlert, self.presentedRequest != configuration.request {
                    self.ownedAlert = nil
                    self.presentedRequest = nil
                    alert.dismiss(animated: false)
                }
                guard configuration.isActive, let request = configuration.request,
                      self.consumedRequest != request, self.ownedAlert == nil else { return }
                if let root = self.view.window?.rootViewController {
                    var presenter = root
                    while let presented = presenter.presentedViewController {
                        presenter = presented
                    }
                    // Leave other alerts and in-flight sheet transitions alone.
                    if !(presenter is UIAlertController),
                       !presenter.isBeingPresented, !presenter.isBeingDismissed,
                       presenter.view.window != nil {
                        let alert = self.makeAlert(for: request)
                        self.ownedAlert = alert
                        self.presentedRequest = request
                        presenter.present(alert, animated: true)
                        return
                    }
                }
                do { try await Task.sleep(for: .milliseconds(250)) }
                catch { return }
            }
        }
    }

    func stop() {
        presentationTask?.cancel()
        presentationTask = nil
        configuration = nil
        ownedAlert?.dismiss(animated: false)
        ownedAlert = nil
    }

    private func makeAlert(for request: AppRootAlert) -> UIAlertController {
        let alert: UIAlertController
        switch request {
        case .manualAppleRevocation:
            alert = UIAlertController(
                title: "Finish Sign in with Apple Cleanup",
                message: "Your Naturebook deletion is already continuing. Because this Apple-linked account predates automatic token revocation, open Settings > [your name] > Sign in with Apple > Naturebook, then choose Delete or Stop Using. You can also follow Apple’s web instructions.",
                preferredStyle: .alert
            )
            addAction("Open Apple Instructions", to: alert, for: request) { $0.openAppleInstructions() }
            addAction("I Revoked Access", to: alert, for: request) { $0.resolveAppleRevocation() }
        case .appUpdate:
            alert = UIAlertController(
                title: AppUpdatePresentation.title, message: AppUpdatePresentation.message,
                preferredStyle: .alert
            )
            addAction("Update app", to: alert, for: request) { $0.updateApp() }
            addAction("Not now", style: .cancel, to: alert, for: request) { $0.dismissUpdate() }
        }
        return alert
    }

    private func addAction(
        _ title: String, style: UIAlertAction.Style = .default,
        to alert: UIAlertController, for request: AppRootAlert,
        perform: @escaping (AppRootAlertBridge) -> Void
    ) {
        alert.addAction(UIAlertAction(title: title, style: style) { [weak self] _ in
            guard let self, let configuration = self.configuration,
                  configuration.request == request else { return }
            self.consumedRequest = request
            perform(configuration)
        })
    }
}
