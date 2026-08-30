import Combine
import Foundation
import UIKit

@MainActor
enum CaptureWorkspaceKeyboardService {
    static var willShowNotifications: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillShowNotification
        )
    }

    static var willHideNotifications: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillHideNotification
        )
    }

    static func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    static func isSoftwareKeyboardVisible(
        from notification: Notification
    ) -> Bool {
        guard let endFrame = notification.userInfo?[
            UIResponder.keyboardFrameEndUserInfoKey
        ] as? CGRect else {
            return true
        }
        let screenBounds = UIScreen.main.bounds
        let visibleKeyboardHeight = max(0, screenBounds.maxY - endFrame.minY)
        return visibleKeyboardHeight > 80
    }
}
