import SwiftUI

struct ImagesCarousel: View {
    // MARK: - Dependencies
    @Environment(InferenceEngine.self) var inferenceEngine

    // MARK: - Properties
    let scanId: String?
    let refUrls: [String]
    let validHistoricImagePaths: [String]
    let hasLive: Bool
    let liveCount: Int
    let totalImages: Int

    // MARK: - State
    @State private var selectedIndex: Int = 0

    // MARK: - Body
    var body: some View {
        if totalImages > 0 {
            NativePageCarousel(selectedIndex: $selectedIndex, pages: carouselPages)
                // scanId only — totalImages changes async when validHistoricImagePaths resolves.
                // Keying on scanId prevents a full rebuild (and snap-back to page 0) on those updates.
                .id(scanId ?? "null")
                .ignoresSafeArea(.all, edges: .top)
                .overlay(alignment: .bottom) { paginationDots }
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [.black.opacity(0.4), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                    .allowsHitTesting(false)
                }
        }
    }

    // MARK: - Page Construction
    /// Pages are built eagerly so every UIHostingController exists before the user swipes.
    /// This ensures AsyncLocalImageView.task fires immediately for all pages — images are
    /// already loading in the background before the user reaches them.
    private var carouselPages: [AnyView] {
        var pages: [AnyView] = []
        if hasLive {
            for data in inferenceEngine.activeDisplayDatas {
                pages.append(AnyView(LiveCapturePageView(data: data)))
            }
        }
        for path in validHistoricImagePaths {
            pages.append(AnyView(
                AsyncLocalImageView(
                    path: path,
                    fallbackImageUrl: nil,
                    onImageLoadFailed: { handleImageFailure(identifier: path) }
                )
            ))
        }
        for urlString in refUrls {
            pages.append(AnyView(
                AsyncLocalImageView(
                    path: nil,
                    fallbackImageUrl: urlString,
                    onImageLoadFailed: { handleImageFailure(identifier: urlString) }
                )
            ))
        }
        return pages
    }

    // MARK: - Action Handlers
    private func handleImageFailure(identifier: String) {
        if totalImages > 1 {
            inferenceEngine.dropInvalidCarouselImage(identifier)
            if selectedIndex >= totalImages - 1 {
                selectedIndex = max(0, totalImages - 2)
            }
        }
    }
}

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
private struct NativePageCarousel: UIViewControllerRepresentable {
    @Binding var selectedIndex: Int
    let pages: [AnyView]

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

        // Grow: pages added async after makeCoordinator was called (validHistoricImagePaths resolution).
        if coordinator.controllers.count < pages.count {
            while coordinator.controllers.count < pages.count {
                let hc = UIHostingController(rootView: pages[coordinator.controllers.count])
                hc.view.backgroundColor = .clear
                hc.view.clipsToBounds = true
                coordinator.controllers.append(hc)
            }
            needsDataSourceReset = true
        }

        // Shrink: a page was removed (e.g., image failure via handleImageFailure).
        // Must trim before pushing rootView updates so the stale controller is gone.
        if coordinator.controllers.count > pages.count {
            coordinator.controllers = Array(coordinator.controllers.prefix(pages.count))
            needsDataSourceReset = true
        }

        // Push updated SwiftUI state into the live hosting controllers.
        for (i, controller) in coordinator.controllers.enumerated() where i < pages.count {
            controller.rootView = pages[i]
        }

        // Force UIPageViewController to re-query its neighbors after the pool changes.
        if needsDataSourceReset {
            uiViewController.dataSource = nil
            uiViewController.dataSource = coordinator
        }

        // Reflect programmatic index changes — including forced navigation away from a removed page.
        guard
            let currentVC = uiViewController.viewControllers?.first,
            let currentVCIndex = coordinator.controllers.firstIndex(where: { $0 === currentVC })
        else {
            // Current VC was trimmed from the pool (image failure on the displayed page).
            // handleImageFailure already adjusted selectedIndex; navigate there immediately.
            if let target = coordinator.controllers[safe: selectedIndex] {
                uiViewController.setViewControllers([target], direction: .reverse, animated: false)
            }
            return
        }

        guard currentVCIndex != selectedIndex,
              let target = coordinator.controllers[safe: selectedIndex]
        else { return }

        let direction: UIPageViewController.NavigationDirection = selectedIndex > currentVCIndex ? .forward : .reverse
        uiViewController.setViewControllers([target], direction: direction, animated: true)
    }

    // MARK: - Coordinator
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        @Binding var selectedIndex: Int
        /// All hosting controllers are instantiated up-front. Their SwiftUI views (and any
        /// .task closures inside them) begin executing as soon as the carousel appears.
        /// Mutable so updateUIViewController can append controllers added after async page resolution.
        var controllers: [UIHostingController<AnyView>]

        init(selectedIndex: Binding<Int>, pages: [AnyView]) {
            _selectedIndex = selectedIndex
            self.controllers = pages.map {
                let hc = UIHostingController(rootView: $0)
                hc.view.backgroundColor = .clear
                hc.view.clipsToBounds = true
                return hc
            }
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

// MARK: - Live Capture Page
/// Decodes raw Data → UIImage in a detached task so the main thread is never blocked
/// during render, preventing frame drops when the carousel first opens.
private struct LiveCapturePageView: View {
    let data: Data
    @State private var decoded: UIImage? = nil

    var body: some View {
        Group {
            if let img = decoded {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task {
            // UIImage(data:) is synchronous — decode it off the main actor to avoid stalling
            // the 120Hz render loop for large captures on carousel open.
            let img = await Task.detached(priority: .userInitiated) {
                autoreleasepool {
                    UIImage(data: data)
                }
            }.value
            decoded = img
        }
    }
}

// MARK: - Layout Subcomponents
private extension ImagesCarousel {

    @ViewBuilder
    var paginationDots: some View {
        if totalImages > 1 {
            HStack(spacing: 8) {
                ForEach(0..<totalImages, id: \.self) { index in
                    Circle()
                        .fill(index == selectedIndex ? Color.white : Color.white.opacity(0.4))
                        .frame(width: 6, height: 6)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.2))
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 40)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedIndex)
        }
    }
}


