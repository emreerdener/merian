import SwiftUI
import UIKit

// MARK: - Zoom Page View Controller
/// Wraps a SwiftUI page view in a UIScrollView, providing native pinch-to-zoom and pan.
///
/// Gesture coexistence strategy:
/// - `ZoomScrollPanDelegate` makes `scrollView.panGestureRecognizer` return false from
///   `gestureRecognizerShouldBegin` when `zoomScale == minimumZoomScale (1.0)`. At 1×
///   the UIPageViewController's own scroll view wins the horizontal swipe normally.
/// - Once the user pinches to any zoom > 1×, the pan delegate allows the inner scroll
///   view to handle drags, letting the user explore the zoomed image freely.
/// - On release of the pinch OR end of a drag while zoomed, `snapBackToIdentity` springs
///   both scale and content offset back to 1× / zero simultaneously.
final class ZoomPageViewController: UIViewController {
    private let scrollView = ZoomScrollView()
    private let hostingController: UIHostingController<AnyView>

    var rootView: AnyView {
        get { hostingController.rootView }
        set { hostingController.rootView = newValue }
    }

    init(page: AnyView) {
        hostingController = UIHostingController(rootView: page)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 4.0
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .clear
        scrollView.clipsToBounds = true

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        addChild(hostingController)
        hostingController.view.backgroundColor = .clear
        hostingController.view.clipsToBounds = true
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: scrollView.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            hostingController.view.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            hostingController.view.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
        hostingController.didMove(toParent: self)
    }
}

extension ZoomPageViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        hostingController.view
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        snapBackToIdentity(scrollView)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView.zoomScale > scrollView.minimumZoomScale else { return }
        // Cancel any pending deceleration so the snap-back animation takes over cleanly.
        if decelerate {
            scrollView.setContentOffset(scrollView.contentOffset, animated: false)
        }
        snapBackToIdentity(scrollView)
    }

    private func snapBackToIdentity(_ scrollView: UIScrollView) {
        UIView.animate(
            withDuration: 0.38,
            delay: 0,
            usingSpringWithDamping: 0.72,
            initialSpringVelocity: 0.3,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            scrollView.setZoomScale(1.0, animated: false)
            scrollView.contentOffset = .zero
        }
    }
}

// MARK: - Zoom Scroll View
/// UIScrollView subclass that blocks its pan gesture at minimum zoom scale, allowing
/// UIPageViewController's swipe to win at 1×. Replacing panGestureRecognizer.delegate
/// directly throws NSInvalidArgumentException at runtime — UIKit requires the scroll view
/// itself to remain the pan gesture's delegate. Overriding gestureRecognizerShouldBegin
/// in a subclass is the only safe interception point.
final class ZoomScrollView: UIScrollView {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer {
            return zoomScale > minimumZoomScale + 0.01
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}
