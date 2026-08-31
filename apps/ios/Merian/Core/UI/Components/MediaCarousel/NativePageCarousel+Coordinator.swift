import SwiftUI
import UIKit

extension NativePageCarousel {
    final class Coordinator:
        NSObject,
        UIPageViewControllerDataSource,
        UIPageViewControllerDelegate {
        @Binding var selectedIndex: Int
        var pages: [NativePageCarouselPage]
        var controllers: [ZoomPageViewController]

        init(
            selectedIndex: Binding<Int>,
            pages: [NativePageCarouselPage]
        ) {
            _selectedIndex = selectedIndex
            self.pages = pages
            controllers = pages.map {
                ZoomPageViewController(page: $0.view)
            }
        }

        static func requiresDataSourceReset(
            previousPages: [NativePageCarouselPage],
            nextPages: [NativePageCarouselPage]
        ) -> Bool {
            previousPages != nextPages
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let index = controllers.firstIndex(where: {
                $0 === viewController
            }), index > 0 else { return nil }
            return controllers[index - 1]
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let index = controllers.firstIndex(where: {
                $0 === viewController
            }), index < controllers.count - 1 else { return nil }
            return controllers[index + 1]
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed,
                  let current = pageViewController.viewControllers?.first,
                  let index = controllers.firstIndex(where: {
                      $0 === current
                  }) else { return }
            selectedIndex = index
        }
    }
}
