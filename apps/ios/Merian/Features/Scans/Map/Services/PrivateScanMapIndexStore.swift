import Combine
import Foundation
import Observation
import SwiftData
import UIKit

enum PrivateScanMapMediaSource: Equatable, Sendable {
    case json(String)
    case items([SerializedMediaItem])

    var snapshot: CapturedMediaSnapshot {
        switch self {
        case .json(let json):
            CapturedMediaSnapshot(jsonString: json)
        case .items(let items):
            CapturedMediaSnapshot(items: items)
        }
    }
}

struct PrivateScanMapRecordProjection: Equatable, Sendable {
    let id: String
    let latitude: Double
    let longitude: Double
    let commonName: String
    let scientificName: String
    let userIdentificationOverride: String?
    let timestamp: Date
    let locationName: String?
    let taxonomyKingdom: String?
    let taxonomyClass: String?
    let coverImagePath: String?
    let referenceImageUrl: String?
    let isLocallyArchived: Bool
    let canResolveReferenceImage: Bool
    let mediaSource: PrivateScanMapMediaSource

    var mapPoint: PrivateScanMapPoint? {
        PrivateScanMapPoint.projected(
            id: id,
            latitude: latitude,
            longitude: longitude,
            commonName: commonName,
            scientificName: scientificName,
            userIdentificationOverride: userIdentificationOverride,
            timestamp: timestamp,
            locationName: locationName,
            taxonomyKingdom: taxonomyKingdom,
            taxonomyClass: taxonomyClass,
            coverImagePath: coverImagePath,
            referenceImageUrl: referenceImageUrl,
            isLocallyArchived: isLocallyArchived,
            canResolveReferenceImage: canResolveReferenceImage,
            mediaSnapshot: mediaSource.snapshot
        )
    }
}

struct PrivateScanMapIndexSnapshot: Equatable, Sendable {
    static let empty = PrivateScanMapIndexSnapshot(
        revision: 0,
        spatialRevision: 0,
        previewSnapshot: .empty,
        interactiveSnapshot: .empty
    )

    let revision: UInt64
    let spatialRevision: UInt64
    let previewSnapshot: PrivateScanMapPreviewSnapshot
    let interactiveSnapshot: PrivateScanMapSnapshot
}

@ModelActor
actor PrivateScanMapDatabaseActor {
    func fetchRecordProjections() throws -> [PrivateScanMapRecordProjection] {
        let descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.isBiological == true },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        return try modelContext.fetch(descriptor).compactMap { record in
            guard let latitude = record.gpsLatitude,
                  let longitude = record.gpsLongitude,
                  PrivateScanMapRegion.isValidCoordinate(
                      latitude: latitude,
                      longitude: longitude
                  ) else {
                return nil
            }

            let mediaSource: PrivateScanMapMediaSource
            if let capturedMediaJSON = record.capturedMediaJSON {
                mediaSource = .json(capturedMediaJSON)
            } else {
                mediaSource = .items(record.serializedCapturedMediaItems)
            }

            return PrivateScanMapRecordProjection(
                id: record.id,
                latitude: latitude,
                longitude: longitude,
                commonName: record.commonName,
                scientificName: record.scientificName,
                userIdentificationOverride: record.userIdentificationOverride,
                timestamp: record.timestamp,
                locationName: record.locationName,
                taxonomyKingdom: record.taxonomyKingdom,
                taxonomyClass: record.taxonomyClass,
                coverImagePath: record.coverImagePath,
                referenceImageUrl: record.referenceImageUrl,
                isLocallyArchived: record.isLocallyArchived,
                canResolveReferenceImage: ScanThumbnailBackfillCandidate(
                    missingVisualFallbackFor: record
                ) != nil,
                mediaSource: mediaSource
            )
        }
    }

    func fetchReferenceFallbackCandidates(
        scanIds: [String]
    ) throws -> [ScanThumbnailBackfillCandidate] {
        var candidates: [ScanThumbnailBackfillCandidate] = []
        candidates.reserveCapacity(scanIds.count)

        for scanId in scanIds {
            var descriptor = FetchDescriptor<LocalScanRecord>(
                predicate: #Predicate { $0.id == scanId }
            )
            descriptor.fetchLimit = 1
            guard let record = try modelContext.fetch(descriptor).first,
                  let candidate = ScanThumbnailBackfillCandidate(
                      missingVisualFallbackFor: record
                  ) else {
                continue
            }
            candidates.append(candidate)
        }

        return candidates
    }
}

protocol PrivateScanMapIndexServing: Sendable {
    func refresh() async throws -> PrivateScanMapIndexSnapshot
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
}

@MainActor
@Observable
final class PrivateScanMapStore {
    private(set) var snapshot = PrivateScanMapIndexSnapshot.empty

    @ObservationIgnored private var indexService: (any PrivateScanMapIndexServing)?
    @ObservationIgnored private var modelContainer: ModelContainer?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var referenceFallbackTask: Task<Void, Never>?
    @ObservationIgnored private var requestedRefreshGeneration: UInt64 = 0
    @ObservationIgnored private var pendingReferenceFallbackIds: Set<String> = []
    @ObservationIgnored private var referenceFallbackAttemptDates: [String: Date] = [:]
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private let previewRenderer: PrivateScanMapPreviewRenderer

    private let referenceFallbackBatchLimit = 12
    private let referenceFallbackRetryInterval: TimeInterval = 15 * 60

    init(
        indexService: (any PrivateScanMapIndexServing)? = nil,
        eventStream: (any AppEventStreaming)? = nil,
        previewRenderer: PrivateScanMapPreviewRenderer = PrivateScanMapPreviewRenderer()
    ) {
        self.indexService = indexService
        self.previewRenderer = previewRenderer
        if let eventStream {
            bind(eventStream: eventStream)
        }
    }

    func configure(
        modelContainer: ModelContainer,
        eventStream: any AppEventStreaming
    ) {
        self.modelContainer = modelContainer
        if indexService == nil {
            indexService = PrivateScanMapIndexService(
                modelContainer: modelContainer
            )
        }
        bind(eventStream: eventStream)
        requestRefresh()
    }

    func requestReferenceImageFallback(for scanId: String) {
        let normalizedScanId = scanId.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard modelContainer != nil,
              !normalizedScanId.isEmpty else {
            return
        }

        let now = Date.now
        if let attemptDate = referenceFallbackAttemptDates[normalizedScanId],
           now.timeIntervalSince(attemptDate) < referenceFallbackRetryInterval {
            return
        }
        guard pendingReferenceFallbackIds.insert(normalizedScanId).inserted else {
            return
        }

        startReferenceFallbackDrainIfNeeded()
    }

    func requestRefresh() {
        requestedRefreshGeneration &+= 1
        guard refreshTask == nil, indexService != nil else { return }

        refreshTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let generation = requestedRefreshGeneration
                guard let indexService else { break }

                do {
                    let refreshedSnapshot = try await indexService.refresh()
                    guard !Task.isCancelled else { break }
                    if refreshedSnapshot != snapshot {
                        snapshot = refreshedSnapshot
                    }
                } catch is CancellationError {
                    break
                } catch {
                    break
                }

                guard generation != requestedRefreshGeneration else { break }
            }

            refreshTask = nil
        }
    }

    func refresh() async {
        requestRefresh()
        let task = refreshTask
        await task?.value
    }

    func previewImage(
        size: CGSize,
        displayScale: CGFloat,
        userInterfaceStyle: UIUserInterfaceStyle
    ) async -> UIImage? {
        await previewRenderer.image(
            snapshot: snapshot.previewSnapshot,
            revision: snapshot.spatialRevision,
            size: size,
            displayScale: displayScale,
            userInterfaceStyle: userInterfaceStyle
        )
    }

    private func bind(eventStream: any AppEventStreaming) {
        guard cancellables.isEmpty else { return }
        eventStream.publisher
            .sink { [weak self] event in
                guard case .scanLibraryChanged = event else { return }
                self?.requestRefresh()
            }
            .store(in: &cancellables)
    }

    private func startReferenceFallbackDrainIfNeeded() {
        guard referenceFallbackTask == nil,
              modelContainer != nil,
              !pendingReferenceFallbackIds.isEmpty else {
            return
        }

        referenceFallbackTask = Task { [weak self] in
            await self?.drainReferenceFallbacks()
        }
    }

    private func drainReferenceFallbacks() async {
        defer {
            referenceFallbackTask = nil
            startReferenceFallbackDrainIfNeeded()
        }

        while !Task.isCancelled,
              let modelContainer,
              !pendingReferenceFallbackIds.isEmpty {
            let scanIds = Array(
                pendingReferenceFallbackIds
                    .sorted()
                    .prefix(referenceFallbackBatchLimit)
            )
            pendingReferenceFallbackIds.subtract(scanIds)

            let attemptDate = Date.now
            for scanId in scanIds {
                referenceFallbackAttemptDates[scanId] = attemptDate
            }

            let databaseActor = PrivateScanMapDatabaseActor(
                modelContainer: modelContainer
            )
            let candidates: [ScanThumbnailBackfillCandidate]
            do {
                candidates = try await databaseActor
                    .fetchReferenceFallbackCandidates(scanIds: scanIds)
            } catch {
                continue
            }
            guard !candidates.isEmpty else { continue }

            let updatedScanIds = await ScanThumbnailBackfillActor.shared.backfill(
                records: candidates,
                modelContainer: modelContainer
            )
            guard !updatedScanIds.isEmpty else { continue }

            await refresh()
        }
    }
}
