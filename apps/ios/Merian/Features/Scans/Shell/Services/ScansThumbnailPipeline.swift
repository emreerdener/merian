import Foundation
import SwiftData

@MainActor
struct ScansThumbnailPipeline {
    typealias ImagePrefetchRecord = (
        imagePath: String?,
        fallbackURL: String?
    )

    struct Dependencies {
        let registerRecoveryMappings: @MainActor ([LocalScanRecord]) -> Void
        let resolveLocalImageURL: @MainActor (URL) -> URL?
        let prefetchImages: @MainActor (
            [ImagePrefetchRecord],
            _ maxDimension: Int
        ) -> Void
        let prefetchAudio: @MainActor (
            _ audioPaths: [String],
            _ maxDimension: Int
        ) -> Void
        let backfill: @MainActor (
            _ candidates: [ScanThumbnailBackfillCandidate],
            _ modelContainer: ModelContainer
        ) async -> Set<String>
        let enqueueCloudRepair: @MainActor (
            _ sourceURL: URL,
            _ localURL: URL
        ) async -> Void
        let publishLibraryChanged: @MainActor () -> Void

        @MainActor
        static var live: Self {
            let container = AppDIContainer.shared
            return Self(
                registerRecoveryMappings: { records in
                    LocalScanMediaRecoveryResolver.registerRecoveryMappings(
                        for: records
                    )
                },
                resolveLocalImageURL: { sourceURL in
                    LocalScanMediaRecoveryResolver.existingLocalImageURL(
                        for: sourceURL
                    )
                },
                prefetchImages: { records, maxDimension in
                    LocalImageLoader.shared.prefetch(
                        records: records.map {
                            (
                                imagePath: $0.imagePath,
                                fallbackUrl: $0.fallbackURL
                            )
                        },
                        maxDimension: maxDimension
                    )
                },
                prefetchAudio: { audioPaths, maxDimension in
                    AudioSpectrogramThumbnailLoader.shared.prefetch(
                        audioPaths: audioPaths,
                        maxDimension: maxDimension
                    )
                },
                backfill: { candidates, modelContainer in
                    await ScanThumbnailBackfillActor.shared.backfill(
                        records: candidates,
                        modelContainer: modelContainer
                    )
                },
                enqueueCloudRepair: { sourceURL, localURL in
                    await CloudScanImageRepairActor.shared.enqueue(
                        sourceUrl: sourceURL,
                        localUrl: localURL
                    )
                },
                publishLibraryChanged: {
                    container.appEventPublisher.send(.scanLibraryChanged)
                }
            )
        }
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies? = nil) {
        self.dependencies = dependencies ?? .live
    }

    /// Warms leading media and schedules repair work without making the view
    /// aware of loaders, actors, filesystem resolution, or app events.
    func refresh(
        records: [LocalScanRecord],
        maxDimension: Int,
        modelContainer: ModelContainer,
        isOnline: Bool
    ) {
        dependencies.registerRecoveryMappings(records)

        let leadingPresentations = records.prefix(18).map(
            \.scanThumbnailPresentation
        )
        dependencies.prefetchImages(
            leadingPresentations.map {
                (
                    imagePath: $0.imagePath,
                    fallbackURL: $0.fallbackImageUrl
                )
            },
            maxDimension
        )
        dependencies.prefetchAudio(
            leadingPresentations.compactMap(\.audioPath),
            maxDimension
        )

        if isOnline {
            enqueueRecoverableCloudImages(from: records)
        }

        let backfillCandidates = records.compactMap(
            ScanThumbnailBackfillCandidate.init(record:)
        )
        guard !backfillCandidates.isEmpty else { return }

        Task(priority: .utility) {
            let updatedScanIDs = await dependencies.backfill(
                backfillCandidates,
                modelContainer
            )
            guard !updatedScanIDs.isEmpty else { return }
            dependencies.publishLibraryChanged()
        }
    }

    private func enqueueRecoverableCloudImages(
        from records: [LocalScanRecord]
    ) {
        var seenSourceURLs: Set<String> = []
        var recoveries: [(sourceURL: URL, localURL: URL)] = []

        for record in records {
            let mediaPaths = [record.coverImagePath].compactMap { $0 }
                + record.capturedMediaSnapshot.thumbnailImagePaths

            for mediaPath in mediaPaths {
                guard let sourceURL = SecureTransportPolicy.httpsURL(
                    from: mediaPath
                ),
                    seenSourceURLs.insert(sourceURL.absoluteString).inserted,
                    let localURL = dependencies.resolveLocalImageURL(
                        sourceURL
                    ) else {
                    continue
                }
                recoveries.append((sourceURL: sourceURL, localURL: localURL))
            }
        }

        guard !recoveries.isEmpty else { return }
        Task(priority: .utility) {
            for recovery in recoveries {
                await dependencies.enqueueCloudRepair(
                    recovery.sourceURL,
                    recovery.localURL
                )
            }
        }
    }
}
