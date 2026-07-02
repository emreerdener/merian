import SwiftUI

// MARK: - GBIF Heatmap Map View

/// Renders a world-level GBIF occurrence density heatmap by compositing a static base map
/// entirely removing MapKit CPU overhead, and overlaying the fetched GBIF Zoom-0 tile.
/// Both images share the exact same Web Mercator projection and world extent.
struct GBIFHeatmapMapView: View {
    private enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case noTaxonKey
        case noData
        case serviceUnavailable
        case failed

        var overlayMessage: String? {
            switch self {
            case .noTaxonKey, .noData:
                return "No distribution data available"
            case .serviceUnavailable:
                return "Habitat data not available"
            case .failed:
                return "Distribution map unavailable"
            case .idle, .loading, .loaded:
                return nil
            }
        }
    }

    private enum FetchResult {
        case image(UIImage)
        case state(LoadState)
    }

    let taxonKey: Int?
    var showsMissingTaxonKeyFallback: Bool = true

    @State private var tileImage: UIImage?
    @State private var loadState: LoadState = .idle
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var isInteracting: Bool = false

    var body: some View {
        ZStack {
            // The map layer scales and pans independently
            ZStack {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.42, green: 0.73, blue: 0.96),
                            Color(red: 0.31, green: 0.63, blue: 0.90)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    Image("world-map-base")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFill()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                if let image = tileImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .scaleEffect(zoomScale)
            .offset(panOffset)

            // 2-finger gesture catcher remains fixed so translation deltas are accurate
            PinchPanOverlay(
                scale: $zoomScale,
                offset: $panOffset,
                isInteracting: $isInteracting
            )
        }
        .overlay(alignment: .bottom) {
            if let message = overlayMessage {
                Text(message)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .padding(.bottom, 12)
            }
        }
        .interactiveDismissDisabled(isInteracting)
        .task(id: taxonKey) {
            tileImage = nil
            loadState = taxonKey == nil ? .noTaxonKey : .loading

            let result = await fetchGBIFTile()
            guard !Task.isCancelled else { return }

            switch result {
            case .image(let image):
                tileImage = image
                loadState = .loaded
            case .state(let state):
                loadState = state
            }
        }
    }

    // MARK: - Private

    // Isolated session for GBIF tile fetches. Short timeout — the tile is best-effort;
    // a missing heatmap is better than stalling the InsightSheet scroll.
    private static let externalAPISession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    private var overlayMessage: String? {
        guard let message = loadState.overlayMessage else { return nil }
        if loadState == .noTaxonKey && !showsMissingTaxonKeyFallback {
            return nil
        }
        return message
    }

    /// Fetches the GBIF density tile at zoom level 0 — one tile covers the entire world!
    private func fetchGBIFTile() async -> FetchResult {
        guard let key = taxonKey,
              let url = URL(string: "https://api.gbif.org/v2/map/occurrence/density/0/0/0@2x.png?taxonKey=\(key)&style=classic.poly&bin=hex&hexPerTile=135")
        else { return .state(.noTaxonKey) }

        do {
            let (data, response) = try await GBIFHeatmapMapView.externalAPISession.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .state(.failed)
            }

            switch httpResponse.statusCode {
            case 200:
                break
            case 204, 404:
                return .state(.noData)
            case 503:
                return .state(.serviceUnavailable)
            case 200..<300:
                if data.isEmpty {
                    return .state(.noData)
                }
            default:
                return .state(.failed)
            }

            guard !data.isEmpty else { return .state(.noData) }

            if let mimeType = httpResponse.mimeType,
               !mimeType.lowercased().hasPrefix("image/") {
                return .state(.failed)
            }

            // Offload CPU-intensive image decompression from the MainActor
            let decodeTask: Task<UIImage?, Never> = Task.detached(priority: .userInitiated) {
                autoreleasepool {
                    guard let cgImage = ImageDownsampler.downsample(data: data, maxSize: 2048, stripAlpha: false) else {
                        return nil
                    }
                    return UIImage(cgImage: cgImage)
                }
            }
            let image = await decodeTask.value

            guard let image else { return .state(.failed) }
            return .image(image)
        } catch {
            return .state(.failed)
        }
    }
}

// MARK: - Native 2-Finger Gesture Bridge
private struct PinchPanOverlay: UIViewRepresentable {
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var isInteracting: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isOpaque = false
        view.backgroundColor = .clear
        view.layer.backgroundColor = UIColor.clear.cgColor

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.isOpaque = false
        uiView.backgroundColor = .clear
        uiView.layer.backgroundColor = UIColor.clear.cgColor
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PinchPanOverlay
        var startScale: CGFloat = 1.0
        var startOffset: CGSize = .zero
        
        var isPinching = false
        var isPanning = false

        init(_ parent: PinchPanOverlay) { self.parent = parent }
        
        func updateScrollLock(for view: UIView) {
            let isActive = isPinching || isPanning
            view.enclosingScrollView?.isScrollEnabled = !isActive
            if parent.isInteracting != isActive {
                parent.isInteracting = isActive
            }
        }

        @objc func handlePinch(_ sender: UIPinchGestureRecognizer) {
            guard let view = sender.view else { return }
            switch sender.state {
            case .began:
                isPinching = true
                updateScrollLock(for: view)
                startScale = parent.scale
            case .changed:
                let newScale = startScale * sender.scale
                parent.scale = newScale < 1.0 ? 1.0 - (1.0 - newScale) * 0.3 : newScale
            case .ended, .cancelled, .failed:
                isPinching = false
                updateScrollLock(for: view)
                snapBack()
            default: break
            }
        }

        @objc func handlePan(_ sender: UIPanGestureRecognizer) {
            guard let view = sender.view else { return }
            switch sender.state {
            case .began:
                isPanning = true
                updateScrollLock(for: view)
                startOffset = parent.offset
            case .changed:
                let trans = sender.translation(in: view)
                parent.offset = CGSize(width: startOffset.width + trans.x, height: startOffset.height + trans.y)
            case .ended, .cancelled, .failed:
                isPanning = false
                updateScrollLock(for: view)
                snapBack()
            default: break
            }
        }

        func snapBack() {
            // Only snap back if BOTH gestures have terminated
            guard !isPinching && !isPanning else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                parent.scale = 1.0
                parent.offset = .zero
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
    }
}

private extension UIView {
    var enclosingScrollView: UIScrollView? {
        var view: UIView? = self
        while let current = view {
            if let scrollView = current as? UIScrollView {
                return scrollView
            }
            view = current.superview
        }
        return nil
    }
}
