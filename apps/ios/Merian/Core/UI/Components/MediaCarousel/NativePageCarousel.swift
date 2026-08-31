import SwiftUI
import UIKit

/// Wraps `UIPageViewController` so every hosted page is created eagerly and its
/// native swipe recognizer can coexist with sheet presentation gestures.
struct NativePageCarousel: UIViewControllerRepresentable {
    @Binding var selectedIndex: Int
    let pages: [NativePageCarouselPage]

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedIndex: $selectedIndex, pages: pages)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageViewController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 0]
        )
        pageViewController.dataSource = context.coordinator
        pageViewController.delegate = context.coordinator
        pageViewController.view.backgroundColor = .clear
        pageViewController.view.clipsToBounds = true

        let initial = context.coordinator.controllers[safe: selectedIndex]
            ?? context.coordinator.controllers.first
        if let initial {
            pageViewController.setViewControllers(
                [initial],
                direction: .forward,
                animated: false
            )
        }
        return pageViewController
    }

    func updateUIViewController(
        _ pageViewController: UIPageViewController,
        context: Context
    ) {
        let coordinator = context.coordinator
        let needsDataSourceReset = Coordinator.requiresDataSourceReset(
            previousPages: coordinator.pages,
            nextPages: pages
        )

        if !pages.isEmpty, selectedIndex >= pages.count {
            DispatchQueue.main.async {
                selectedIndex = max(0, pages.count - 1)
            }
        }

        var newControllers: [ZoomPageViewController] = []
        for newPage in pages {
            if let oldIndex = coordinator.pages.firstIndex(of: newPage) {
                let controller = coordinator.controllers[oldIndex]
                controller.rootView = newPage.view
                newControllers.append(controller)
            } else {
                newControllers.append(
                    ZoomPageViewController(page: newPage.view)
                )
            }
        }

        coordinator.controllers = newControllers
        coordinator.pages = pages

        if needsDataSourceReset {
            pageViewController.dataSource = nil
            pageViewController.dataSource = coordinator

            let safeIndex = max(
                0,
                min(selectedIndex, coordinator.controllers.count - 1)
            )
            if let target = coordinator.controllers[safe: safeIndex] {
                pageViewController.setViewControllers(
                    [target],
                    direction: .forward,
                    animated: false
                )
            }
        }

        guard let currentViewController =
            pageViewController.viewControllers?.first else { return }
        let currentIndex = coordinator.controllers.firstIndex {
            $0 === currentViewController
        }

        guard currentIndex == nil || currentIndex != selectedIndex else {
            return
        }
        let safeIndex = max(
            0,
            min(selectedIndex, coordinator.controllers.count - 1)
        )
        guard let target = coordinator.controllers[safe: safeIndex] else {
            return
        }
        let direction: UIPageViewController.NavigationDirection
        if let currentIndex {
            direction = safeIndex > currentIndex ? .forward : .reverse
        } else {
            direction = .forward
        }
        pageViewController.setViewControllers(
            [target],
            direction: direction,
            animated: currentIndex != nil
        )
    }
}
