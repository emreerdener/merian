import SwiftUI
import UIKit

struct ExploreDetailZoomView<Content: View>: UIViewControllerRepresentable {
    private let content: Content
    private let onSingleTap: (() -> Void)?
    private let onDoubleTap: (() -> Void)?

    init(
        onSingleTap: (() -> Void)? = nil,
        onDoubleTap: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.onSingleTap = onSingleTap
        self.onDoubleTap = onDoubleTap
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .clear

        let scrollView = ExploreDetailZoomScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 4.0
        scrollView.minimumZoomScale = 1.0
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.clipsToBounds = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let hostingController = UIHostingController(rootView: content)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        viewController.view.addSubview(scrollView)
        scrollView.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: viewController.view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostingController.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            hostingController.view.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        viewController.addChild(hostingController)
        hostingController.didMove(toParent: viewController)

        context.coordinator.hostingController = hostingController
        context.coordinator.scrollView = scrollView
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.onDoubleTap = onDoubleTap

        if onDoubleTap != nil {
            let doubleTapRecognizer = UITapGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleDoubleTap(_:))
            )
            doubleTapRecognizer.numberOfTapsRequired = 2
            scrollView.addGestureRecognizer(doubleTapRecognizer)
            context.coordinator.doubleTapRecognizer = doubleTapRecognizer
        }

        if onSingleTap != nil {
            let singleTapRecognizer = UITapGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleSingleTap(_:))
            )
            if let doubleTapRecognizer = context.coordinator.doubleTapRecognizer {
                singleTapRecognizer.require(toFail: doubleTapRecognizer)
            }
            scrollView.addGestureRecognizer(singleTapRecognizer)
            context.coordinator.singleTapRecognizer = singleTapRecognizer
        }

        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.hostingController?.rootView = content
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.onDoubleTap = onDoubleTap
        context.coordinator.layoutHostedContent(in: uiViewController)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiViewController: UIViewController,
        context: Context
    ) -> CGSize? {
        ExploreDetailZoomLayoutPolicy.resolvedSize(
            width: proposal.width,
            height: proposal.height
        )
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<Content>?
        weak var scrollView: UIScrollView?
        var onSingleTap: (() -> Void)?
        var onDoubleTap: (() -> Void)?
        weak var singleTapRecognizer: UITapGestureRecognizer?
        weak var doubleTapRecognizer: UITapGestureRecognizer?

        func layoutHostedContent(in viewController: UIViewController) {
            viewController.view.setNeedsLayout()
            viewController.view.layoutIfNeeded()
            scrollView?.setNeedsLayout()
            scrollView?.layoutIfNeeded()
            hostingController?.view.setNeedsLayout()
            hostingController?.view.layoutIfNeeded()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostingController?.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let view = hostingController?.view else { return }

            let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
            let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
            view.center = CGPoint(
                x: scrollView.contentSize.width * 0.5 + offsetX,
                y: scrollView.contentSize.height * 0.5 + offsetY
            )
        }

        func scrollViewDidEndZooming(
            _ scrollView: UIScrollView,
            with view: UIView?,
            atScale scale: CGFloat
        ) {
            snapBackToIdentity(scrollView)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 else { return }

            if decelerate {
                scrollView.setContentOffset(scrollView.contentOffset, animated: false)
            }

            snapBackToIdentity(scrollView)
        }

        @objc
        func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView,
                  scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 else {
                return
            }

            onSingleTap?()
        }

        @objc
        func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView,
                  scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 else {
                return
            }

            onDoubleTap?()
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
}
private final class ExploreDetailZoomScrollView: UIScrollView {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer {
            return zoomScale > minimumZoomScale + 0.01
        }

        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}
