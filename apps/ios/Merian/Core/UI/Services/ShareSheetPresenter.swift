import UIKit

public enum ShareSheetPresenter {
    @MainActor
    public static func present(
        items: [Any],
        onDismiss: (@MainActor () -> Void)? = nil
    ) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            onDismiss?()
            return
        }

        let activityViewController = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        activityViewController.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in
                onDismiss?()
            }
        }

        var topViewController = rootViewController
        while let presentedViewController = topViewController.presentedViewController {
            topViewController = presentedViewController
        }

        if let popover = activityViewController.popoverPresentationController {
            popover.sourceView = topViewController.view
            popover.sourceRect = CGRect(
                x: topViewController.view.bounds.midX,
                y: topViewController.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }

        topViewController.present(activityViewController, animated: true)
    }
}
