import SwiftUI
import UIKit

// SwiftUI has no native API for disabling pager bounce. This probe walks up the UIKit
// hierarchy from inside the ScrollView's content to find the backing UIScrollView
// and hard-disables bounce so neither edge rubber-bands.
struct ScrollBounceDisabler: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { _ProbeView() }
    func updateUIView(_ uiView: UIView, context: Context) {}

    private class _ProbeView: UIView {
        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            DispatchQueue.main.async { [weak self] in
                var current: UIView? = self?.superview
                while let view = current {
                    if let sv = view as? UIScrollView {
                        sv.bounces = false
                        return
                    }
                    current = view.superview
                }
            }
        }
    }
}
