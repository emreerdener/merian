import SwiftUI

// SwiftUI exposes scroll-driven keyboard dismissal, but not a passive tap-outside hook
// for this inline composer, so this probe attaches a non-blocking recognizer to the
// backing UIScrollView and resigns first responder when the user taps elsewhere.
struct ExploreKeyboardDismissTapRecognizer: UIViewRepresentable {
    let isEnabled: Bool
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onTap = onTap
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: uiView)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEnabled = false
        var onTap: (() -> Void)?

        private lazy var tapRecognizer: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            return recognizer
        }()

        func attachIfNeeded(from probeView: UIView) {
            var current: UIView? = probeView.superview
            while let view = current {
                if let scrollView = view as? UIScrollView {
                    guard tapRecognizer.view !== scrollView else { return }
                    tapRecognizer.view?.removeGestureRecognizer(tapRecognizer)
                    scrollView.addGestureRecognizer(tapRecognizer)
                    return
                }
                current = view.superview
            }
        }

        @objc
        private func handleTap() {
            guard isEnabled else { return }
            onTap?()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard isEnabled else { return false }
            guard let touchedView = touch.view else { return true }
            return !touchedView.hasAncestor(ofType: UITextField.self)
                && !touchedView.hasAncestor(ofType: UITextView.self)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

private extension UIView {
    func hasAncestor<T: UIView>(ofType type: T.Type) -> Bool {
        var current: UIView? = self
        while let view = current {
            if view is T {
                return true
            }
            current = view.superview
        }
        return false
    }
}
