import SwiftUI

struct ZoomableScrollView<Content: View>: UIViewControllerRepresentable {
    private var content: Content
    private var onSwipeDown: (() -> Void)?
    
    init(onSwipeDown: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.onSwipeDown = onSwipeDown
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 4.0
        scrollView.minimumZoomScale = 1.0
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        
        let hostingController = UIHostingController(rootView: content)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(scrollView)
        scrollView.addSubview(hostingController.view)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: vc.view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),
            
            hostingController.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostingController.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            hostingController.view.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
        
        vc.addChild(hostingController)
        hostingController.didMove(toParent: vc)
        
        context.coordinator.hostingController = hostingController
        
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        if onSwipeDown != nil {
            let swipeDown = UISwipeGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleSwipeDown(_:))
            )
            swipeDown.direction = .down
            swipeDown.cancelsTouchesInView = false
            swipeDown.delegate = context.coordinator
            scrollView.addGestureRecognizer(swipeDown)
        }
        
        return vc
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.hostingController?.rootView = content
        context.coordinator.onSwipeDown = onSwipeDown
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onSwipeDown: onSwipeDown)
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var hostingController: UIHostingController<Content>?
        var onSwipeDown: (() -> Void)?

        init(onSwipeDown: (() -> Void)?) {
            self.onSwipeDown = onSwipeDown
        }
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return hostingController?.view
        }
        
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let view = hostingController?.view else { return }
            let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
            let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
            view.center = CGPoint(x: scrollView.contentSize.width * 0.5 + offsetX,
                                  y: scrollView.contentSize.height * 0.5 + offsetY)
        }
        
        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }
            if scrollView.zoomScale > 1.0 {
                scrollView.setZoomScale(1.0, animated: true)
            } else {
                let point = recognizer.location(in: hostingController?.view)
                let scrollSize = scrollView.bounds.size
                let size = CGSize(width: scrollSize.width / 2.0, height: scrollSize.height / 2.0)
                let origin = CGPoint(x: point.x - size.width / 2.0, y: point.y - size.height / 2.0)
                scrollView.zoom(to: CGRect(origin: origin, size: size), animated: true)
            }
        }

        @objc func handleSwipeDown(_ recognizer: UISwipeGestureRecognizer) {
            onSwipeDown?()
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer is UISwipeGestureRecognizer,
                  let scrollView = gestureRecognizer.view as? UIScrollView else {
                return true
            }
            return scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer is UISwipeGestureRecognizer
        }
    }
}
