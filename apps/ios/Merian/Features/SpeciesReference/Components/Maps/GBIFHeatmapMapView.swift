import SwiftUI
import UIKit

/// Renders a world-level GBIF occurrence-density heatmap by compositing a
/// static base map and the fetched GBIF zoom-zero tile. Both images share the
/// same Web Mercator projection and world extent.
struct GBIFHeatmapMapView: View {
    let taxonKey: Int?
    var showsMissingTaxonKeyFallback: Bool

    @State private var viewModel: GBIFHeatmapViewModel
    @State private var zoomScale: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var isInteracting = false

    init(
        taxonKey: Int?,
        showsMissingTaxonKeyFallback: Bool = true,
        dependencies: GBIFHeatmapDependencies = .live
    ) {
        self.taxonKey = taxonKey
        self.showsMissingTaxonKeyFallback = showsMissingTaxonKeyFallback
        _viewModel = State(
            initialValue: GBIFHeatmapViewModel(dependencies: dependencies)
        )
    }

    var body: some View {
        ZStack {
            mapLayers
                .scaleEffect(zoomScale)
                .offset(panOffset)

            GBIFHeatmapPinchPanOverlay(
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
            await viewModel.load(taxonKey: taxonKey)
        }
    }

    private var mapLayers: some View {
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

            if let image = viewModel.tileImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var overlayMessage: String? {
        guard let message = viewModel.loadState.overlayMessage else {
            return nil
        }
        if viewModel.loadState == .noTaxonKey &&
            !showsMissingTaxonKeyFallback {
            return nil
        }
        return message
    }
}

private struct GBIFHeatmapPinchPanOverlay: UIViewRepresentable {
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var isInteracting: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isOpaque = false
        view.backgroundColor = .clear
        view.layer.backgroundColor = UIColor.clear.cgColor

        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        view.isOpaque = false
        view.backgroundColor = .clear
        view.layer.backgroundColor = UIColor.clear.cgColor
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private var parent: GBIFHeatmapPinchPanOverlay
        private var startScale: CGFloat = 1
        private var startOffset: CGSize = .zero
        private var isPinching = false
        private var isPanning = false

        init(_ parent: GBIFHeatmapPinchPanOverlay) {
            self.parent = parent
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
                parent.scale = newScale < 1
                    ? 1 - (1 - newScale) * 0.3
                    : newScale
            case .ended, .cancelled, .failed:
                isPinching = false
                updateScrollLock(for: view)
                snapBack()
            default:
                break
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
                let translation = sender.translation(in: view)
                parent.offset = CGSize(
                    width: startOffset.width + translation.x,
                    height: startOffset.height + translation.y
                )
            case .ended, .cancelled, .failed:
                isPanning = false
                updateScrollLock(for: view)
                snapBack()
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        private func updateScrollLock(for view: UIView) {
            let isActive = isPinching || isPanning
            view.enclosingScrollView?.isScrollEnabled = !isActive
            if parent.isInteracting != isActive {
                parent.isInteracting = isActive
            }
        }

        private func snapBack() {
            guard !isPinching && !isPanning else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                parent.scale = 1
                parent.offset = .zero
            }
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
