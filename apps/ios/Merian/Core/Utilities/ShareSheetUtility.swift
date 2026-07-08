import UIKit

public struct ShareSheetUtility {
    @MainActor
    public static func present(items: [Any], onDismiss: (() -> Void)? = nil) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootVC = window.rootViewController else {
            onDismiss?()
            return
        }
        
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            onDismiss?()
        }
        
        // Traverse safely up the stack to avoid overlapping presentation bounds
        var topController = rootVC
        while let presented = topController.presentedViewController {
            topController = presented
        }
        
        // Set anchor for iPad popover presentation.
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topController.view
            popover.sourceRect = CGRect(x: topController.view.bounds.midX, y: topController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        topController.present(activityVC, animated: true)
    }
}
