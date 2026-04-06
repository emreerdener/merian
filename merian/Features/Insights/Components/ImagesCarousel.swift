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
        Group {
            if totalImages > 0 {
                NativePageCarousel(selectedIndex: $selectedIndex, pages: carouselPages)
                    // scanId only — totalImages changes async when validHistoricImagePaths resolves.
                    // Keying on scanId prevents a full rebuild (and snap-back to page 0) on those updates.
                    .id(scanId ?? "null")
                    .ignoresSafeArea(.all, edges: .top)
                    .overlay {
                        if inferenceEngine.isProcessing {
                            AnalyzingVisualEffectsView()
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 1.2), value: inferenceEngine.isProcessing)
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
            } else {
                Color.black
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.all, edges: .top)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: totalImages > 0)
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
        } else {
            for path in validHistoricImagePaths {
                pages.append(AnyView(
                    AsyncLocalImageView(
                        path: path,
                        fallbackImageUrl: nil,
                        onImageLoadFailed: { handleImageFailure(identifier: path) }
                    )
                ))
            }
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
                coordinator.controllers.append(ZoomPageViewController(page: pages[coordinator.controllers.count]))
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
        /// All page view controllers are instantiated up-front. Each wraps its SwiftUI content
        /// in a UIScrollView so pinch-zoom and pan work natively per-page without conflicting
        /// with UIPageViewController's swipe or the sheet's pan gesture.
        /// Mutable so updateUIViewController can append controllers added after async page resolution.
        var controllers: [ZoomPageViewController]

        init(selectedIndex: Binding<Int>, pages: [AnyView]) {
            _selectedIndex = selectedIndex
            self.controllers = pages.map { ZoomPageViewController(page: $0) }
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
private let liveCaptureCache = NSCache<NSNumber, UIImage>()

/// Executes downsampling directly on layout evaluation. Modern A-Series silicon resolves 
/// the ImageIO downsample significantly fast enough to guarantee the Carousel
/// launches synchronously pre-mounted with the photo, completely eradicating transient black frames.
private struct LiveCapturePageView: View {
    let data: Data
    
    private var instantImage: UIImage? {
        let key = NSNumber(value: data.hashValue)
        if let cached = liveCaptureCache.object(forKey: key) {
            return cached
        }
        
        // Force synchronous decode natively
        let img = autoreleasepool { () -> UIImage? in
            if let cgImage = ImageDownsampler.shared.downsample(data: data, maxSize: 2048) {
                return UIImage(cgImage: cgImage)
            }
            return nil
        }
        
        if let img {
            liveCaptureCache.setObject(img, forKey: key)
        }
        return img
    }

    var body: some View {
        Group {
            if let img = instantImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

// MARK: - Layout Subcomponents
private extension ImagesCarousel {

    @ViewBuilder
    var paginationDots: some View {
        ZStack {
            if totalImages > 1 && !inferenceEngine.isProcessing {
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
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity
                ))
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: inferenceEngine.isProcessing)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: totalImages)
    }
}

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
private final class ZoomPageViewController: UIViewController {
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
private final class ZoomScrollView: UIScrollView {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer {
            return zoomScale > minimumZoomScale + 0.01
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}

// MARK: - Analyzing Visual Effects
private struct AnalyzingVisualEffectsView: View {
    @State private var pulseOpacity: Double = 0.0

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.black)
                .opacity(pulseOpacity)
                .allowsHitTesting(false)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true).delay(1)) {
                pulseOpacity = 0.4
            }
        }
    }
}
