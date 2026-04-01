import SwiftUI

// MARK: - GBIF Heatmap Map View

/// Renders a world-level GBIF occurrence density heatmap by compositing a static base map
/// entirely removing MapKit CPU overhead, and overlaying the fetched GBIF Zoom-0 tile.
/// Both images share the exact same Web Mercator projection and world extent.
struct GBIFHeatmapMapView: View {
    let taxonKey: Int?

    @State private var tileImage: UIImage?
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var isInteracting: Bool = false

    var body: some View {
        ZStack {
            // The map layer scales and pans independently
            ZStack {
                Image("WorldMapBase")
                    .resizable()
                    .scaledToFill()
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
        .interactiveDismissDisabled(isInteracting)
        .task(id: taxonKey) {
            tileImage = await fetchGBIFTile()
        }
    }

    // MARK: - Private

    /// Fetches the GBIF density tile at zoom level 0 — one tile covers the entire world!
    private func fetchGBIFTile() async -> UIImage? {
        guard let key = taxonKey,
              let url = URL(string: "https://api.gbif.org/v2/map/occurrence/density/0/0/0@2x.png?taxonKey=\(key)&style=classic.poly&bin=hex&hexPerTile=135")
        else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Native 2-Finger Gesture Bridge
private struct PinchPanOverlay: UIViewRepresentable {
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var isInteracting: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

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

    func updateUIView(_ uiView: UIView, context: Context) {}
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
