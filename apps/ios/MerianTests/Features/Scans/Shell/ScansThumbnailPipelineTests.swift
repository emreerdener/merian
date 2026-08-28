import SwiftData
import XCTest

@testable import Merian

@MainActor
final class ScansThumbnailPipelineTests: XCTestCase {
    func testRefreshPrefetchesOnlyLeadingEighteenRecords() throws {
        let context = try makeContext()
        let records = (0..<20).map { index in
            makeRecord(
                id: "scan-\(index)",
                coverImagePath: "file:///scan-\(index).jpg"
            )
        }
        var registeredIDs: [String] = []
        var prefetchedImages: [ScansThumbnailPipeline.ImagePrefetchRecord] = []
        var prefetchedAudioPaths: [String] = []
        let pipeline = ScansThumbnailPipeline(
            dependencies: .init(
                registerRecoveryMappings: { records in
                    registeredIDs = records.map(\.id)
                },
                resolveLocalImageURL: { _ in
                    XCTFail("Offline refresh must not resolve cloud repairs")
                    return nil
                },
                prefetchImages: { records, _ in
                    prefetchedImages = records
                },
                prefetchAudio: { paths, _ in
                    prefetchedAudioPaths = paths
                },
                backfill: { _, _ in
                    XCTFail("Visual records must not request backfill")
                    return []
                },
                enqueueCloudRepair: { _, _ in
                    XCTFail("Offline refresh must not enqueue repairs")
                },
                publishLibraryChanged: {
                    XCTFail("No backfill should publish an invalidation")
                }
            )
        )

        pipeline.refresh(
            records: records,
            maxDimension: 300,
            modelContainer: context.container,
            isOnline: false
        )

        XCTAssertEqual(registeredIDs, records.map(\.id))
        XCTAssertEqual(prefetchedImages.count, 18)
        XCTAssertEqual(prefetchedImages.first?.imagePath, "file:///scan-0.jpg")
        XCTAssertEqual(prefetchedImages.last?.imagePath, "file:///scan-17.jpg")
        XCTAssertTrue(prefetchedAudioPaths.isEmpty)
    }

    func testRefreshPrefetchesOnlyLeadingEighteenAudioRecords() async throws {
        let context = try makeContext()
        let records = try (0..<20).map { index in
            makeRecord(
                id: "scan-\(index)",
                coverImagePath: nil,
                capturedMediaJSON: try capturedAudioJSON(
                    path: "audio-\(index).wav"
                )
            )
        }
        let backfillStarted = expectation(description: "Backfill started")
        var prefetchedAudioPaths: [String] = []
        let pipeline = ScansThumbnailPipeline(
            dependencies: .init(
                registerRecoveryMappings: { _ in },
                resolveLocalImageURL: { _ in nil },
                prefetchImages: { _, _ in },
                prefetchAudio: { paths, _ in
                    prefetchedAudioPaths = paths
                },
                backfill: { candidates, _ in
                    XCTAssertEqual(candidates.count, 20)
                    backfillStarted.fulfill()
                    return []
                },
                enqueueCloudRepair: { _, _ in },
                publishLibraryChanged: {
                    XCTFail("An empty backfill must not publish invalidation")
                }
            )
        )

        pipeline.refresh(
            records: records,
            maxDimension: 300,
            modelContainer: context.container,
            isOnline: false
        )
        await fulfillment(of: [backfillStarted], timeout: 1)

        XCTAssertEqual(prefetchedAudioPaths.count, 18)
        XCTAssertEqual(prefetchedAudioPaths.first, "audio-0.wav")
        XCTAssertEqual(prefetchedAudioPaths.last, "audio-17.wav")
    }

    func testOnlineRefreshResolvesAndEnqueuesCloudRepair() async throws {
        let context = try makeContext()
        let sourceURL = try XCTUnwrap(
            URL(string: "https://media.merian.app/public_uploads/pro/scan.jpg")
        )
        let localURL = URL(fileURLWithPath: "/tmp/scan.jpg")
        let repairEnqueued = expectation(description: "Cloud repair enqueued")
        var receivedRepair: (source: URL, local: URL)?
        let pipeline = ScansThumbnailPipeline(
            dependencies: .init(
                registerRecoveryMappings: { _ in },
                resolveLocalImageURL: { receivedSourceURL in
                    XCTAssertEqual(receivedSourceURL, sourceURL)
                    return localURL
                },
                prefetchImages: { _, _ in },
                prefetchAudio: { _, _ in },
                backfill: { _, _ in [] },
                enqueueCloudRepair: { receivedSourceURL, receivedLocalURL in
                    receivedRepair = (receivedSourceURL, receivedLocalURL)
                    repairEnqueued.fulfill()
                },
                publishLibraryChanged: { }
            )
        )

        pipeline.refresh(
            records: [
                makeRecord(
                    id: "scan",
                    coverImagePath: sourceURL.absoluteString
                )
            ],
            maxDimension: 300,
            modelContainer: context.container,
            isOnline: true
        )
        await fulfillment(of: [repairEnqueued], timeout: 1)

        XCTAssertEqual(receivedRepair?.source, sourceURL)
        XCTAssertEqual(receivedRepair?.local, localURL)
    }

    func testReferenceBackfillPublishesLibraryInvalidation() async throws {
        let context = try makeContext()
        let backfillStarted = expectation(description: "Backfill started")
        let invalidationPublished = expectation(
            description: "Library invalidation published"
        )
        let pipeline = ScansThumbnailPipeline(
            dependencies: .init(
                registerRecoveryMappings: { _ in },
                resolveLocalImageURL: { _ in nil },
                prefetchImages: { _, _ in },
                prefetchAudio: { _, _ in },
                backfill: { candidates, receivedContainer in
                    XCTAssertTrue(receivedContainer === context.container)
                    XCTAssertEqual(candidates.map(\.scanId), ["scan"])
                    backfillStarted.fulfill()
                    return ["scan"]
                },
                enqueueCloudRepair: { _, _ in },
                publishLibraryChanged: {
                    invalidationPublished.fulfill()
                }
            )
        )

        pipeline.refresh(
            records: [makeRecord(id: "scan", coverImagePath: nil)],
            maxDimension: 300,
            modelContainer: context.container,
            isOnline: false
        )
        await fulfillment(
            of: [backfillStarted, invalidationPublished],
            timeout: 1,
            enforceOrder: true
        )
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        return ModelContext(container)
    }

    private func makeRecord(
        id: String,
        coverImagePath: String?,
        capturedMediaJSON: String = "[]"
    ) -> LocalScanRecord {
        LocalScanRecord(
            id: id,
            speciesId: "species-\(id)",
            scientificName: "Species \(id)",
            commonName: "Species \(id)",
            capturedMediaJSON: capturedMediaJSON,
            coverImagePath: coverImagePath,
            isBiological: true
        )
    }

    private func capturedAudioJSON(path: String) throws -> String {
        let data = try JSONEncoder().encode([
            SerializedMediaItem.audio(.documents(path))
        ])
        return try XCTUnwrap(String(bytes: data, encoding: .utf8))
    }
}
