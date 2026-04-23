import SwiftUI
import UIKit

extension NativePageCarousel {
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        @Binding var selectedIndex: Int
        var pages: [CarouselPageItem]
        var controllers: [ZoomPageViewController]

        init(selectedIndex: Binding<Int>, pages: [CarouselPageItem]) {
            _selectedIndex = selectedIndex
            self.pages = pages
            self.controllers = pages.map { ZoomPageViewController(page: $0.view) }
        }

        // MARK: UIPageViewControllerDataSource
        func pageViewController(
            _ pvc: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let idx = controllers.firstIndex(where: { $0 === viewController }), idx > 0 else { return nil }
            return controllers[idx - 1]
        }

        func pageViewController(
            _ pvc: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let idx = controllers.firstIndex(where: { $0 === viewController }), idx < controllers.count - 1 else { return nil }
            return controllers[idx + 1]
        }

        // MARK: UIPageViewControllerDelegate
        func pageViewController(
            _ pvc: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard
                completed,
                let current = pvc.viewControllers?.first,
                let idx = controllers.firstIndex(where: { $0 === current })
            else { return }
            selectedIndex = idx
        }
    }
}
