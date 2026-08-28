import Combine
import Foundation
import Observation
import SwiftData
import UIKit

@MainActor
@Observable
final class PrivateScanMapStore {
    private(set) var snapshot = PrivateScanMapIndexSnapshot.empty
    private(set) var sensitiveResetGeneration: UInt64 = 0

    @ObservationIgnored private var indexService: (any PrivateScanMapIndexServing)?
    @ObservationIgnored private var modelContainer: ModelContainer?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshRunID: UUID?
    @ObservationIgnored private var referenceFallbackTask: Task<Void, Never>?
    @ObservationIgnored private var referenceFallbackRunID: UUID?
    @ObservationIgnored private var requestedRefreshGeneration: UInt64 = 0
    @ObservationIgnored private var privacyEpoch: UInt64 = 0
    @ObservationIgnored private var pendingReferenceFallbackIds: Set<String> = []
    @ObservationIgnored private var referenceFallbackAttemptDates: [String: Date] = [:]
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var previewRenderer: any PrivateScanMapPreviewRendering
    @ObservationIgnored private var usesConfiguredIndexService = false

    private let referenceFallbackBatchLimit = 12
    private let referenceFallbackRetryInterval: TimeInterval = 15 * 60

    init(
        indexService: (any PrivateScanMapIndexServing)? = nil,
        eventStream: (any AppEventStreaming)? = nil,
        previewRenderer: any PrivateScanMapPreviewRendering =
            PrivateScanMapPreviewRenderer()
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
            usesConfiguredIndexService = true
        }
        bind(eventStream: eventStream)
        requestRefresh()
    }

    /// Synchronously removes all presentation access to owner-only map data.
    /// Detached actors are also asked to erase their private caches; epoch
    /// checks prevent their cooperative cancellation from publishing stale work.
    func resetSensitiveState() {
        privacyEpoch &+= 1
        sensitiveResetGeneration &+= 1
        requestedRefreshGeneration &+= 1
        snapshot = .empty

        refreshTask?.cancel()
        refreshTask = nil
        refreshRunID = nil
        referenceFallbackTask?.cancel()
        referenceFallbackTask = nil
        referenceFallbackRunID = nil
        pendingReferenceFallbackIds.removeAll(keepingCapacity: false)
        referenceFallbackAttemptDates.removeAll(keepingCapacity: false)

        let retiredIndexService = indexService
        let retiredPreviewRenderer = previewRenderer
        if usesConfiguredIndexService, let modelContainer {
            indexService = PrivateScanMapIndexService(
                modelContainer: modelContainer
            )
        } else {
            indexService = nil
        }
        previewRenderer = PrivateScanMapPreviewRenderer()

        Task {
            await retiredIndexService?.reset()
        }
        Task {
            await retiredPreviewRenderer.reset()
        }
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

        let runID = UUID()
        let epoch = privacyEpoch
        refreshRunID = runID
        refreshTask = Task { [weak self] in
            await self?.drainRefreshes(runID: runID, epoch: epoch)
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
        let epoch = privacyEpoch
        let renderer = previewRenderer
        let requestedSnapshot = snapshot
        let image = await renderer.image(
            snapshot: requestedSnapshot.previewSnapshot,
            revision: requestedSnapshot.spatialRevision,
            size: size,
            displayScale: displayScale,
            userInterfaceStyle: userInterfaceStyle
        )
        guard !Task.isCancelled, epoch == privacyEpoch else { return nil }
        return image
    }

    private func drainRefreshes(runID: UUID, epoch: UInt64) async {
        defer {
            if refreshRunID == runID {
                refreshTask = nil
                refreshRunID = nil
            }
        }

        while !Task.isCancelled, epoch == privacyEpoch {
            let generation = requestedRefreshGeneration
            guard let indexService else { break }

            do {
                let refreshedSnapshot = try await indexService.refresh()
                guard !Task.isCancelled, epoch == privacyEpoch else { break }
                if refreshedSnapshot != snapshot {
                    snapshot = refreshedSnapshot
                }
            } catch is CancellationError {
                break
            } catch {
                guard epoch == privacyEpoch,
                      generation != requestedRefreshGeneration else {
                    break
                }
                continue
            }

            guard generation != requestedRefreshGeneration else { break }
        }
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

        let runID = UUID()
        let epoch = privacyEpoch
        referenceFallbackRunID = runID
        referenceFallbackTask = Task { [weak self] in
            await self?.drainReferenceFallbacks(runID: runID, epoch: epoch)
        }
    }

    private func drainReferenceFallbacks(runID: UUID, epoch: UInt64) async {
        defer {
            if referenceFallbackRunID == runID {
                referenceFallbackTask = nil
                referenceFallbackRunID = nil
                if epoch == privacyEpoch {
                    startReferenceFallbackDrainIfNeeded()
                }
            }
        }

        while !Task.isCancelled,
              epoch == privacyEpoch,
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
            guard !Task.isCancelled,
                  epoch == privacyEpoch,
                  !candidates.isEmpty else {
                continue
            }

            let updatedScanIds = await ScanThumbnailBackfillActor.shared.backfill(
                records: candidates,
                modelContainer: modelContainer
            )
            guard !Task.isCancelled,
                  epoch == privacyEpoch,
                  !updatedScanIds.isEmpty else {
                continue
            }

            await refresh()
        }
    }
}
