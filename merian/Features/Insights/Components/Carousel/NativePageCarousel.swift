import SwiftUI
import UIKit

// MARK: - Native UIPageViewController Carousel
/// Wraps UIPageViewController directly rather than going through SwiftUI's TabView(.page) shim.
///
/// Two problems TabView(.page) cannot solve:
/// 1. SwiftUI lazily instantiates tab pages, so AsyncLocalImageView.task only fires when the
///    user swipes to a page — the image loads *during* the transition, causing layout thrashing
///    and the stuck-mid-swipe feeling.
/// 2. TabView(.page)'s gesture recogniser conflicts with the sheet's pan gesture in .sheet context,
///    producing the occasional halfway-frozen swipe.
///
/// UIPageViewController fixes both: all UIHostingController instances are pre-created (images
/// start loading immediately), and UIPageViewController's internal UIScrollView correctly defers
/// to the sheet's gesture recogniser without requiring any manual workarounds.
struct NativePageCarousel: UIViewControllerRepresentable {
    @Binding var selectedIndex: Int
    let pages: [CarouselPageItem]

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedIndex: $selectedIndex, pages: pages)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 0]
        )
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        pvc.view.backgroundColor = .clear
        pvc.view.clipsToBounds = true

        let initial = context.coordinator.controllers[safe: selectedIndex]
                   ?? context.coordinator.controllers.first
        if let initial {
            pvc.setViewControllers([initial], direction: .forward, animated: false)
        }
        return pvc
    }

    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        var needsDataSourceReset = false
        
        // Clamp the selectedIndex if the pages array shrunk async.
        if !pages.isEmpty && selectedIndex >= pages.count {
            DispatchQueue.main.async {
                selectedIndex = max(0, pages.count - 1)
            }
        }

        // Identity-based diffing: reconstruct the controllers array by matching IDs.
        // This ensures that if a page is deleted from the middle/start of the array,
        // we keep the exact instances of the remaining pages (like AudioPlayback), 
        // preserving their state and AVPlayer instances.
        var newControllers: [ZoomPageViewController] = []
        
        for newPage in pages {
            if let oldIndex = coordinator.pages.firstIndex(of: newPage) {
                // The exact same page identity exists — preserve its controller!
                newControllers.append(coordinator.controllers[oldIndex])
            } else {
                // It is structurally new (e.g., .liveImage -> .image) or a brand new insertion.
                newControllers.append(ZoomPageViewController(page: newPage.view))
                
                // If the user is actively viewing the index where this structurally new item is appearing,
                // we forcibly reload the data source to transition the UI immediately.
                if let newIndex = pages.firstIndex(of: newPage), selectedIndex == newIndex {
                    needsDataSourceReset = true
                }
            }
        }
        
        coordinator.controllers = newControllers
        coordinator.pages = pages

        // Force UIPageViewController to re-query its neighbors after the active view controller changes.
        if needsDataSourceReset {
            uiViewController.dataSource = nil
            uiViewController.dataSource = coordinator
            
            // To prevent a frozen state after a data source change, UIPageViewController demands a setViewControllers call.
            let safeIndex = max(0, min(selectedIndex, coordinator.controllers.count - 1))
            if let target = coordinator.controllers[safe: safeIndex] {
                uiViewController.setViewControllers([target], direction: .forward, animated: false)
            }
        }

        // Reflect programmatic index changes — including forced navigation away from a removed page.
        guard let currentVC = uiViewController.viewControllers?.first else { return }
        let currentVCIndex = coordinator.controllers.firstIndex(where: { $0 === currentVC })

        // If the currently visible VC was removed from the array (orphaned via shrink),
        // or the SwiftUI binding explicitly demanded a new index.
        if currentVCIndex == nil || currentVCIndex != selectedIndex {
            let safeIndex = max(0, min(selectedIndex, coordinator.controllers.count - 1))
            if let target = coordinator.controllers[safe: safeIndex] {
                let direction: UIPageViewController.NavigationDirection
                if let oldIdx = currentVCIndex {
                    direction = safeIndex > oldIdx ? .forward : .reverse
                } else {
                    direction = .forward
                }
                
                // Animate ONLY if it was a standard programmatic index change.
                // If orphaned, snap immediately so they don't see a weird transition from a dead view.
                uiViewController.setViewControllers([target], direction: direction, animated: currentVCIndex != nil)
            }
        }
    }

}
