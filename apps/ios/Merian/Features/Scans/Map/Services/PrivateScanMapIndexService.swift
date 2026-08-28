import Foundation
import SwiftData

protocol PrivateScanMapIndexServing: Sendable {
    func refresh() async throws -> PrivateScanMapIndexSnapshot
    func reset() async
}

extension PrivateScanMapIndexServing {
    func reset() async {}
}

actor PrivateScanMapIndexService: PrivateScanMapIndexServing {
    private struct CachedPoint: Equatable {
        let projection: PrivateScanMapRecordProjection
        let point: PrivateScanMapPoint
    }

    private let modelContainer: ModelContainer
    private var cachedPoints: [String: CachedPoint] = [:]
    private var cachedPreviewPoints: [PrivateScanMapPreviewPoint] = []
    private var revision: UInt64 = 0
    private var spatialRevision: UInt64 = 0

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func refresh() async throws -> PrivateScanMapIndexSnapshot {
        try Task.checkCancellation()
        let databaseActor = PrivateScanMapDatabaseActor(
            modelContainer: modelContainer
        )
        let projections = try await databaseActor.fetchRecordProjections()
        try Task.checkCancellation()

        var nextPoints: [String: CachedPoint] = [:]
        nextPoints.reserveCapacity(projections.count)

        for projection in projections {
            try Task.checkCancellation()
            if let cachedPoint = cachedPoints[projection.id],
               cachedPoint.projection == projection {
                nextPoints[projection.id] = cachedPoint
                continue
            }

            guard let point = projection.mapPoint else { continue }
            nextPoints[projection.id] = CachedPoint(
                projection: projection,
                point: point
            )
        }

        let points = nextPoints.values
            .map(\.point)
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp > rhs.timestamp
                }
                return lhs.id < rhs.id
            }
        let previewPoints = points
            .map {
                PrivateScanMapPreviewPoint(
                    id: $0.id,
                    latitude: $0.latitude,
                    longitude: $0.longitude
                )
            }
            .sorted { $0.id < $1.id }

        if nextPoints != cachedPoints {
            revision &+= 1
        }
        if previewPoints != cachedPreviewPoints {
            spatialRevision &+= 1
        }

        cachedPoints = nextPoints
        cachedPreviewPoints = previewPoints

        return PrivateScanMapIndexSnapshot(
            revision: revision,
            spatialRevision: spatialRevision,
            previewSnapshot: PrivateScanMapPreviewSnapshot(
                points: previewPoints
            ),
            interactiveSnapshot: PrivateScanMapSnapshot(
                points: points,
                revision: revision
            )
        )
    }

    func reset() {
        cachedPoints.removeAll(keepingCapacity: false)
        cachedPreviewPoints.removeAll(keepingCapacity: false)
        revision = 0
        spatialRevision = 0
    }
}
