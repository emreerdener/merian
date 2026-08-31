import SwiftUI
import UIKit

/// Wraps a SwiftUI page in a native zoom surface. At identity scale the inner
/// pan recognizer yields to the outer pager; zoom and offset spring back when an
/// interaction ends.
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

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
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
            hostingController.view.topAnchor.constraint(
                equalTo: scrollView.topAnchor
            ),
            hostingController.view.bottomAnchor.constraint(
                equalTo: scrollView.bottomAnchor
            ),
            hostingController.view.leadingAnchor.constraint(
                equalTo: scrollView.leadingAnchor
            ),
            hostingController.view.trailingAnchor.constraint(
                equalTo: scrollView.trailingAnchor
            ),
            hostingController.view.widthAnchor.constraint(
                equalTo: scrollView.widthAnchor
            ),
            hostingController.view.heightAnchor.constraint(
                equalTo: scrollView.heightAnchor
            )
        ])
        hostingController.didMove(toParent: self)
    }
}

extension ZoomPageViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        hostingController.view
    }

    func scrollViewDidEndZooming(
        _ scrollView: UIScrollView,
        with view: UIView?,
        atScale scale: CGFloat
    ) {
        snapBackToIdentity(scrollView)
    }

    func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        guard scrollView.zoomScale > scrollView.minimumZoomScale else { return }
        if decelerate {
            scrollView.setContentOffset(
                scrollView.contentOffset,
                animated: false
            )
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
            scrollView.setZoomScale(1, animated: false)
            scrollView.contentOffset = .zero
        }
    }
}

private final class ZoomScrollView: UIScrollView {
    override func gestureRecognizerShouldBegin(
        _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if gestureRecognizer === panGestureRecognizer {
            return zoomScale > minimumZoomScale + 0.01
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}
