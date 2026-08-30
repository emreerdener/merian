import SwiftUI
import UIKit

/// UIKit-hosted vertical scrolling kept outside SwiftUI's horizontal pager graph.
struct DescribeVerticalScrollView<Content: View>: UIViewControllerRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIViewController(
        context: Context
    ) -> UIViewController {
        DescribeScrollHostingController(rootView: content)
    }

    func updateUIViewController(
        _ viewController: UIViewController,
        context: Context
    ) {
        guard let controller = viewController as? DescribeScrollHostingController<Content>
        else {
            assertionFailure("DescribeVerticalScrollView received an unexpected controller")
            return
        }
        controller.hostingController.rootView = content
        controller.hostingController.view.invalidateIntrinsicContentSize()
    }
}

private final class DescribeScrollHostingController<Content: View>: UIViewController {
    let hostingController: UIHostingController<Content>

    init(rootView: Content) {
        hostingController = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = UIView()
        rootView.backgroundColor = .clear

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.keyboardDismissMode = .onDrag
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear

        let hostedView = hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.backgroundColor = .clear

        rootView.addSubview(scrollView)
        addChild(hostingController)
        scrollView.addSubview(hostedView)
        hostingController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: rootView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            hostedView.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor
            ),
            hostedView.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor
            ),
            hostedView.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor
            ),
            hostedView.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor
            ),
            hostedView.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor
            ),
            hostedView.heightAnchor.constraint(
                greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor
            )
        ])

        view = rootView
    }
}
