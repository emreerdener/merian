import Foundation
@testable import Merian
import Testing

private actor CloudScanImageRepairProbe {
    struct Snapshot: Sendable {
        let inspectedSourceURLs: [String]
        let generatedFiles: [StagingUploadFile]
        let uploadedObjectKeys: [String]
        let uploadedLocalURLs: [URL]
        let uploadedContentTypes: [String]
        let repairedSourceURLs: [String]
        let repairedObjectKeys: [String]
        let publicationCount: Int
        let events: [String]
    }

    private var inspectedSourceURLs: [String] = []
    private var generatedFiles: [StagingUploadFile] = []
    private var uploadedObjectKeys: [String] = []
    private var uploadedLocalURLs: [URL] = []
    private var uploadedContentTypes: [String] = []
    private var repairedSourceURLs: [String] = []
    private var repairedObjectKeys: [String] = []
    private var publicationCount = 0
    private var events: [String] = []

    func recordInspection(_ sourceURL: String) {
        inspectedSourceURLs.append(sourceURL)
        events.append("inspect")
    }

    func recordGeneration(_ files: [StagingUploadFile]) {
        generatedFiles.append(contentsOf: files)
        events.append("sign")
    }

    func recordUpload(
        _ uploadURL: PreSignedURL,
        localURL: URL,
        contentType: String
    ) {
        uploadedObjectKeys.append(uploadURL.objectKey)
        uploadedLocalURLs.append(localURL)
        uploadedContentTypes.append(contentType)
        events.append("upload")
    }

    func recordRepair(sourceURL: String, objectKey: String) {
        repairedSourceURLs.append(sourceURL)
        repairedObjectKeys.append(objectKey)
        events.append("repair")
    }

    func recordPublication() {
        publicationCount += 1
        events.append("publish")
    }

    func snapshot() -> Snapshot {
        Snapshot(
            inspectedSourceURLs: inspectedSourceURLs,
            generatedFiles: generatedFiles,
            uploadedObjectKeys: uploadedObjectKeys,
            uploadedLocalURLs: uploadedLocalURLs,
            uploadedContentTypes: uploadedContentTypes,
            repairedSourceURLs: repairedSourceURLs,
            repairedObjectKeys: repairedObjectKeys,
            publicationCount: publicationCount,
            events: events
        )
    }
}

private actor CloudScanImageRepairGate {
    private var didEnter = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        guard !didEnter else { return }
        didEnter = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        waiters.forEach { $0.resume() }

        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilEntered() async {
        if didEnter { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func release() {
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

@Suite("Cloud Scan Image Repair")
struct CloudScanImageRepairActorTests {
    @Test func missingImageUsesTheInjectedRepairPipeline() async throws {
        let probe = CloudScanImageRepairProbe()
        let missing = try inspection(status: "missing")
        let repaired = try inspection(
            status: "repaired",
            updatedScanCount: 1,
            updatedPostMediaCount: 2
        )
        let fixedUUID = try #require(
            UUID(uuidString: "11111111-2222-3333-4444-555555555555")
        )
        let uploadURL = PreSignedURL(
            fileName: "repair.webp",
            signedUrl: "https://uploads.example.com/repair",
            objectKey: "staging/user/repair.webp",
            requiredHeaders: [:],
            mediaAssetId: nil,
            mediaSessionId: nil
        )
        let localURL = URL(fileURLWithPath: "/tmp/recovered.webp")
        let sourceURL = try #require(URL(
            string:
                "https://media.merian.app/public_uploads/free/user/recovered.webp?width=900#preview"
        ))
        let canonicalSourceURL =
            "https://media.merian.app/public_uploads/free/user/recovered.webp"

        let repairActor = CloudScanImageRepairActor(
            dependencies: .init(
                shouldRun: { true },
                now: { Date(timeIntervalSince1970: 1_000) },
                fileExists: { $0 == localURL },
                fileSizeBytes: { _ in 42 },
                makeUUID: { fixedUUID },
                inspect: { sourceURL in
                    await probe.recordInspection(sourceURL)
                    return missing
                },
                generateUploadURLs: { files in
                    await probe.recordGeneration(files)
                    return [uploadURL]
                },
                upload: { target, fileURL, contentType in
                    await probe.recordUpload(
                        target,
                        localURL: fileURL,
                        contentType: contentType
                    )
                },
                repair: { sourceURL, objectKey in
                    await probe.recordRepair(
                        sourceURL: sourceURL,
                        objectKey: objectKey
                    )
                    return repaired
                },
                publishLibraryChanged: {
                    await probe.recordPublication()
                }
            )
        )

        await repairActor.enqueue(sourceUrl: sourceURL, localUrl: localURL)
        await repairActor.waitUntilIdle()

        let snapshot = await probe.snapshot()
        #expect(snapshot.inspectedSourceURLs == [canonicalSourceURL])
        #expect(snapshot.generatedFiles == [
            StagingUploadFile(
                fileName:
                    "repair_11111111-2222-3333-4444-555555555555.webp",
                mediaKind: .image,
                contentType: "image/webp",
                sizeBytes: 42
            )
        ])
        #expect(snapshot.uploadedObjectKeys == [uploadURL.objectKey])
        #expect(snapshot.uploadedLocalURLs == [localURL])
        #expect(snapshot.uploadedContentTypes == ["image/webp"])
        #expect(snapshot.repairedSourceURLs == [canonicalSourceURL])
        #expect(snapshot.repairedObjectKeys == [uploadURL.objectKey])
        #expect(snapshot.publicationCount == 1)
        #expect(snapshot.events == [
            "inspect",
            "sign",
            "upload",
            "repair",
            "publish"
        ])
    }

    @Test func duplicateEnqueueDuringInspectionRemainsSingleFlight() async throws {
        let probe = CloudScanImageRepairProbe()
        let gate = CloudScanImageRepairGate()
        let healthy = try inspection(status: "healthy")
        let localURL = URL(fileURLWithPath: "/tmp/recovered.png")
        let sourceURL = try #require(URL(
            string:
                "https://media.merian.app/public_uploads/pro/user/recovered.png?width=500"
        ))
        let duplicateURL = try #require(URL(
            string:
                "HTTPS://MEDIA.MERIAN.APP:443/public_uploads/pro/user/recovered.png#duplicate"
        ))

        let repairActor = CloudScanImageRepairActor(
            dependencies: .init(
                shouldRun: { true },
                now: { Date(timeIntervalSince1970: 1_000) },
                fileExists: { _ in true },
                fileSizeBytes: { _ in 1 },
                makeUUID: { UUID() },
                inspect: { sourceURL in
                    await probe.recordInspection(sourceURL)
                    await gate.suspend()
                    return healthy
                },
                generateUploadURLs: { _ in
                    Issue.record("A healthy image must not request upload URLs")
                    return []
                },
                upload: { _, _, _ in
                    Issue.record("A healthy image must not upload")
                },
                repair: { _, _ in
                    Issue.record("A healthy image must not request repair")
                    return healthy
                },
                publishLibraryChanged: {
                    Issue.record("A healthy image must not publish a change")
                }
            )
        )

        await repairActor.enqueue(sourceUrl: sourceURL, localUrl: localURL)
        await gate.waitUntilEntered()
        await repairActor.enqueue(sourceUrl: duplicateURL, localUrl: localURL)
        await gate.release()
        await repairActor.waitUntilIdle()

        let snapshot = await probe.snapshot()
        #expect(snapshot.inspectedSourceURLs == [
            "https://media.merian.app/public_uploads/pro/user/recovered.png"
        ])
    }

    private func inspection(
        status: String,
        updatedScanCount: Int = 0,
        updatedPostMediaCount: Int = 0
    ) throws -> ScanImageCloudInspection {
        let data = Data(
            """
            {
              "status": "\(status)",
              "replacement_url": null,
              "updated_scan_count": \(updatedScanCount),
              "updated_post_media_count": \(updatedPostMediaCount)
            }
            """.utf8
        )
        return try JSONDecoder().decode(
            ScanImageCloudInspection.self,
            from: data
        )
    }
}
