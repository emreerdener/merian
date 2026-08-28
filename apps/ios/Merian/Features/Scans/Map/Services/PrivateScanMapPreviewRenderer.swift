import MapKit
import UIKit

protocol PrivateScanMapPreviewRendering: Sendable {
    func image(
        snapshot: PrivateScanMapPreviewSnapshot,
        revision: UInt64,
        size: CGSize,
        displayScale: CGFloat,
        userInterfaceStyle: UIUserInterfaceStyle
    ) async -> UIImage?

    func reset() async
}

actor PrivateScanMapPreviewRenderer: PrivateScanMapPreviewRendering {
    private struct CacheKey: Hashable {
        let revision: UInt64
        let widthPixels: Int
        let heightPixels: Int
        let userInterfaceStyle: Int
    }

    private static let maximumCachedImages = 4

    private var cachedImages: [CacheKey: UIImage] = [:]
    private var cacheOrder: [CacheKey] = []
    private var activeSnapshotters: [UUID: MKMapSnapshotter] = [:]
    private var generation: UInt64 = 0
    private var isRetired = false

    func image(
        snapshot: PrivateScanMapPreviewSnapshot,
        revision: UInt64,
        size: CGSize,
        displayScale: CGFloat,
        userInterfaceStyle: UIUserInterfaceStyle
    ) async -> UIImage? {
        guard !isRetired,
              size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0,
              displayScale.isFinite,
              displayScale > 0,
              let region = snapshot.fullExtentRegion else {
            return nil
        }

        let key = CacheKey(
            revision: revision,
            widthPixels: Int((size.width * displayScale).rounded()),
            heightPixels: Int((size.height * displayScale).rounded()),
            userInterfaceStyle: userInterfaceStyle.rawValue
        )
        if let cachedImage = cachedImages[key] {
            return cachedImage
        }
        guard !Task.isCancelled else { return nil }

        let requestedGeneration = generation
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        let traitCollection = UITraitCollection { traits in
            traits.userInterfaceStyle = userInterfaceStyle
            traits.displayScale = displayScale
        }
        options.traitCollection = traitCollection
        let configuration = MKStandardMapConfiguration(
            elevationStyle: .flat,
            emphasisStyle: .muted
        )
        options.preferredConfiguration = configuration

        let snapshotter = MKMapSnapshotter(options: options)
        let requestID = UUID()
        activeSnapshotters[requestID] = snapshotter
        defer {
            activeSnapshotters.removeValue(forKey: requestID)
        }

        let mapSnapshot: MKMapSnapshotter.Snapshot
        do {
            mapSnapshot = try await withTaskCancellationHandler {
                try await snapshotter.start()
            } onCancel: {
                Task {
                    await self.cancelSnapshotter(requestID: requestID)
                }
            }
        } catch {
            return nil
        }

        guard !Task.isCancelled,
              requestedGeneration == generation,
              !isRetired else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat(for: traitCollection)
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: size,
            format: format
        )
        let annotations = PrivateScanMapClusterer.previewAnnotations(
            points: snapshot.points,
            region: region,
            viewportSize: size,
            cellSize: PrivateScanMapClusterer.previewCellSize,
            screenPoint: mapSnapshot.point(for:)
        )
        let renderedImage = renderer.image { context in
            mapSnapshot.image.draw(in: CGRect(origin: .zero, size: size))
            for annotation in annotations {
                let coordinate: CLLocationCoordinate2D
                switch annotation {
                case .point(let point):
                    coordinate = point.coordinate
                case .cluster(let cluster):
                    coordinate = cluster.coordinate
                }

                let imagePoint = mapSnapshot.point(for: coordinate)
                guard imagePoint.x.isFinite,
                      imagePoint.y.isFinite,
                      imagePoint.x >= -32,
                      imagePoint.y >= -32,
                      imagePoint.x <= size.width + 32,
                      imagePoint.y <= size.height + 32 else {
                    continue
                }
                Self.draw(
                    annotation: annotation,
                    centeredAt: imagePoint,
                    in: context.cgContext
                )
            }
        }
        guard !Task.isCancelled,
              requestedGeneration == generation,
              !isRetired else {
            return nil
        }
        insert(renderedImage, for: key)
        return renderedImage
    }

    func reset() {
        isRetired = true
        generation &+= 1
        for snapshotter in activeSnapshotters.values {
            snapshotter.cancel()
        }
        activeSnapshotters.removeAll(keepingCapacity: false)
        cachedImages.removeAll(keepingCapacity: false)
        cacheOrder.removeAll(keepingCapacity: false)
    }

    private func cancelSnapshotter(requestID: UUID) {
        activeSnapshotters[requestID]?.cancel()
    }

    private func insert(_ image: UIImage, for key: CacheKey) {
        cachedImages[key] = image
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)

        while cacheOrder.count > Self.maximumCachedImages {
            let expiredKey = cacheOrder.removeFirst()
            cachedImages.removeValue(forKey: expiredKey)
        }
    }

    private static func draw(
        annotation: PrivateScanMapPreviewAnnotation,
        centeredAt point: CGPoint,
        in context: CGContext
    ) {
        let count: Int?
        let diameter: CGFloat
        switch annotation {
        case .point:
            count = nil
            diameter = 12
        case .cluster(let cluster):
            count = cluster.count
            diameter = 30
        }

        let markerRect = CGRect(
            x: point.x - (diameter / 2),
            y: point.y - (diameter / 2),
            width: diameter,
            height: diameter
        )
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: 1),
            blur: 3,
            color: UIColor.black.withAlphaComponent(0.28).cgColor
        )
        context.setFillColor(UIColor.systemBlue.cgColor)
        context.fillEllipse(in: markerRect)
        context.restoreGState()

        context.saveGState()
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(2)
        context.strokeEllipse(in: markerRect.insetBy(dx: 1, dy: 1))
        context.restoreGState()

        guard let count else { return }
        let text = count.formatted() as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(
                x: point.x - (textSize.width / 2),
                y: point.y - (textSize.height / 2)
            ),
            withAttributes: attributes
        )
    }
}
