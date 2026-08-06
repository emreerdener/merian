import Foundation
@testable import Merian
import Testing
import UIKit

struct LocalImageLoaderTests {
    private actor ConcurrencyProbe {
        private(set) var active = 0
        private(set) var maximum = 0

        func enter() {
            active += 1
            maximum = max(maximum, active)
        }

        func leave() {
            active -= 1
        }
    }

    @Test func secureTransportPolicyAdmitsOnlyCredentialFreeHTTPSRemotes() {
        #expect(
            SecureTransportPolicy.httpsURL(
                from: " https://media.merian.app/path/image.webp?width=900 "
            )?.scheme == "https"
        )
        for rejected in [
            "http://media.merian.app/path/image.webp",
            "ftp://media.merian.app/path/image.webp",
            "https://user:secret@media.merian.app/path/image.webp",
            "https:///path/image.webp",
            "not a URL"
        ] {
            #expect(SecureTransportPolicy.httpsURL(from: rejected) == nil)
        }
    }

    @Test func secureTransportPolicyResolvesLocalMediaWithoutAdmittingHTTP() {
        #expect(
            SecureTransportPolicy.localFileOrHTTPSURL(
                from: "/tmp/image.webp"
            )?.isFileURL == true
        )
        #expect(
            SecureTransportPolicy.localFileOrHTTPSURL(
                from: "file:///tmp/image.webp"
            )?.isFileURL == true
        )
        #expect(
            SecureTransportPolicy.localFileOrHTTPSURL(
                from: "https://media.merian.app/image.webp"
            )?.scheme == "https"
        )
        #expect(
            SecureTransportPolicy.localFileOrHTTPSURL(
                from: "http://media.merian.app/image.webp"
            ) == nil
        )
    }

    @Test func asyncPermitPoolBoundsWorkWithoutBlockingWaits() async {
        let pool = AsyncPermitPool(limit: 2)
        let probe = ConcurrencyProbe()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    guard await pool.acquire() else { return }
                    await probe.enter()
                    try? await Task.sleep(for: .milliseconds(10))
                    await probe.leave()
                    await pool.release()
                }
            }
        }

        let maximum = await probe.maximum
        #expect(maximum == 2)
    }

    @Test func cancelledPermitWaiterDoesNotConsumeReleasedSlot() async {
        let pool = AsyncPermitPool(limit: 1)
        let initialPermit = await pool.acquire()
        #expect(initialPermit)

        let waiter = Task { await pool.acquire() }
        await Task.yield()
        waiter.cancel()
        let cancelledWaiterAcquired = await waiter.value
        #expect(!cancelledWaiterAcquired)

        await pool.release()
        let replacementPermit = await pool.acquire()
        #expect(replacementPermit)
        await pool.release()
    }

    @Test func externalReferenceImagePolicyBlocksOnlyTheDeniedINaturalistMedia() {
        let deniedVariants = [
            "https://inaturalist-open-data.s3.amazonaws.com/photos/605615444/original.jpg",
            "https://inaturalist-open-data.s3.amazonaws.com/photos/605615444/medium.jpg?size=500",
            "HTTPS://INATURALIST-OPEN-DATA.S3.AMAZONAWS.COM/photos/605615444/square.jpg#preview"
        ]

        #expect(deniedVariants.allSatisfy { !ExternalReferenceImagePolicy.isAllowed($0) })
        #expect(ExternalReferenceImagePolicy.isAllowed(
            "https://inaturalist-open-data.s3.amazonaws.com/photos/605615445/original.jpg"
        ))
        #expect(ExternalReferenceImagePolicy.isAllowed(
            "https://api.gbif.org/v1/image/605615444.jpg"
        ))
        #expect(!ExternalReferenceImagePolicy.isAllowed(
            "http://api.gbif.org/v1/image/605615444.jpg"
        ))
        #expect(ExternalReferenceImagePolicy.sanitizedURL(
            "http://media.merian.app/image.webp"
        ) == nil)
    }

    @Test func localImageLoaderRejectsCleartextRemotePathsBeforeDispatch() async {
        let image = await LocalImageLoader.shared.loadImage(
            fromPath: "http://media.merian.app/image.webp",
            fallbackUrl: "http://media.merian.app/fallback.webp",
            maxDimension: 100
        )

        #expect(image == nil)
    }

    @Test func externalReferenceImagePolicyPromotesTheNextLegacyURL() {
        let denied = "https://inaturalist-open-data.s3.amazonaws.com/photos/605615444/original.jpg"
        let safe = "https://live.staticflickr.com/65535/55027456166_642323e641_b.jpg"

        #expect(ExternalReferenceImagePolicy.allowedURLStrings(
            from: " \(denied), \(safe) "
        ) == [safe])
    }

    @Test func localImageLoaderReturnsNilForAnAllBlockedFallbackWithoutDownloading() async {
        let image = await LocalImageLoader.shared.loadImage(
            fromPath: nil,
            fallbackUrl: "https://inaturalist-open-data.s3.amazonaws.com/photos/605615444/large.jpg?download=1",
            maxDimension: 500
        )

        #expect(image == nil)
    }

    @Test func remoteImageRetryPolicyRetriesOnlyTransientHTTPFailures() {
        for statusCode in [408, 425, 429, 500, 502, 503, 599] {
            #expect(RemoteImageRetryPolicy.shouldRetry(statusCode: statusCode))
        }

        for statusCode in [200, 301, 400, 401, 403, 404, 422] {
            #expect(!RemoteImageRetryPolicy.shouldRetry(statusCode: statusCode))
        }
    }

    @Test func remoteImageRetryPolicyDefersOfflineRecoveryUntilReconnect() {
        #expect(RemoteImageRetryPolicy.maximumAttempts == 3)
        #expect(RemoteImageRetryPolicy.shouldRetry(urlErrorCode: .timedOut))
        #expect(RemoteImageRetryPolicy.shouldRetry(urlErrorCode: .cannotConnectToHost))
        #expect(RemoteImageRetryPolicy.shouldRetry(urlErrorCode: .networkConnectionLost))
        #expect(!RemoteImageRetryPolicy.shouldRetry(urlErrorCode: .notConnectedToInternet))
        #expect(!RemoteImageRetryPolicy.shouldRetry(urlErrorCode: .cancelled))
    }

    @Test func localScanMediaRecoveryReconnectsPromotedNameToDocumentsFile() throws {
        let scanId = "2a3ab44a-0981-44b8-85da-f873cc04725f"
        let localFileName = "0B9FC7CE-D81E-4031-979A-454DC9B7DFA7_scan.webp"
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let localURL = temporaryDirectory.appendingPathComponent(localFileName)
        #expect(FileManager.default.createFile(atPath: localURL.path, contents: Data()))

        let remoteURL = try #require(URL(
            string: "https://media.merian.app/public_uploads/free/user/\(scanId)_\(localFileName)?width=900"
        ))
        let recoveredURL = LocalScanMediaRecoveryResolver.existingLocalImageURL(
            for: remoteURL,
            documentsDirectory: temporaryDirectory
        )

        #expect(recoveredURL == localURL)
    }

    @Test func localScanMediaRecoveryUsesRegisteredScanIDMappingWhenCloudNameChanged() throws {
        let localFileName = "\(UUID().uuidString)_scan.webp"
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            LocalScanMediaRecoveryResolver
                .resetRegisteredRecoveryMappingsForTesting()
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let localURL = temporaryDirectory.appendingPathComponent(localFileName)
        #expect(FileManager.default.createFile(
            atPath: localURL.path,
            contents: Data([0x01])
        ))

        let remoteURL = try #require(URL(
            string: "https://media.merian.app/public_uploads/pro/user/\(UUID().uuidString).webp"
        ))
        #expect(LocalScanMediaRecoveryResolver.registerRecoveryMapping(
            remoteURL: remoteURL,
            localFileName: localFileName
        ))

        let recoveredURL = LocalScanMediaRecoveryResolver.existingLocalImageURL(
            for: URL(string: "\(remoteURL.absoluteString)?width=900")!,
            documentsDirectory: temporaryDirectory
        )

        #expect(recoveredURL == localURL)
    }

    @Test func localScanMediaRecoveryUsesHighConfidenceWriteTimestampGroup() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            LocalScanMediaRecoveryResolver
                .resetRegisteredRecoveryMappingsForTesting()
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let primaryName = "\(UUID().uuidString)_scan.webp"
        let additionalName = "\(UUID().uuidString)_additional_1.webp"
        let primaryURL = temporaryDirectory.appendingPathComponent(primaryName)
        let additionalURL = temporaryDirectory.appendingPathComponent(additionalName)
        #expect(FileManager.default.createFile(
            atPath: primaryURL.path,
            contents: Data([0x01])
        ))
        #expect(FileManager.default.createFile(
            atPath: additionalURL.path,
            contents: Data([0x02])
        ))

        let writtenAt = Date(timeIntervalSince1970: 1_784_748_461)
        try FileManager.default.setAttributes(
            [.modificationDate: writtenAt],
            ofItemAtPath: primaryURL.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: writtenAt],
            ofItemAtPath: additionalURL.path
        )

        let remoteURLs = try [
            #require(URL(
                string: "https://media.merian.app/public_uploads/pro/user/\(UUID().uuidString).webp"
            )),
            #require(URL(
                string: "https://media.merian.app/public_uploads/pro/user/\(UUID().uuidString).webp"
            ))
        ]
        #expect(LocalScanMediaRecoveryResolver
            .registerTimestampRecoveryMappingsForTesting(
                scanID: UUID().uuidString,
                timestamp: writtenAt.addingTimeInterval(16),
                remoteImageURLs: remoteURLs,
                documentsDirectory: temporaryDirectory
            ) == 2)

        #expect(LocalScanMediaRecoveryResolver.existingLocalImageURL(
            for: remoteURLs[0],
            documentsDirectory: temporaryDirectory
        ) == primaryURL)
        #expect(LocalScanMediaRecoveryResolver.existingLocalImageURL(
            for: remoteURLs[1],
            documentsDirectory: temporaryDirectory
        ) == additionalURL)
    }

    @Test func localImageLoaderRecoversExploreFallbackURLFromDocuments() async throws {
        let scanId = UUID().uuidString
        let localFileName = "\(UUID().uuidString)_scan.png"
        let localURL = URL.documentsDirectory.appendingPathComponent(localFileName)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let imageData = try #require(image.pngData())
        try imageData.write(to: localURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: localURL) }

        let remoteURL = "https://media.merian.app/public_uploads/free/user/\(scanId)_\(localFileName)"
        let recoveredImage = await LocalImageLoader.shared.loadImage(
            fromPath: nil,
            fallbackUrl: remoteURL,
            maxDimension: 20
        )

        #expect(recoveredImage != nil)
    }

    @Test func localScanMediaRecoveryRejectsNonCaptureAndUnsafeURLs() throws {
        let externalURL = try #require(URL(string: "https://example.com/public_uploads/free/user/image.webp"))
        let avatarURL = try #require(URL(string: "https://media.merian.app/avatars/user/image.webp"))
        let nonImageURL = try #require(URL(
            string: "https://media.merian.app/public_uploads/pro/user/recording.wav"
        ))

        #expect(LocalScanMediaRecoveryResolver.candidateFileNames(for: externalURL).isEmpty)
        #expect(LocalScanMediaRecoveryResolver.candidateFileNames(for: avatarURL).isEmpty)
        #expect(LocalScanMediaRecoveryResolver.candidateFileNames(for: nonImageURL).isEmpty)
    }

    @Test func similarSpeciesDownloadsAreRestoredToSourceOrder() {
        let completionOrder: [(index: Int, value: String?)] = [
            (index: 2, value: "third"),
            (index: 0, value: "first"),
            (index: 1, value: nil)
        ]

        #expect(SimilarSpeciesImageFetcher.orderedLoadedValues(from: completionOrder) == [
            "first",
            "third"
        ])
    }
    
    @Test func testLocalImageLoader_ConcurrentDeduplication() async throws {
        let loader = LocalImageLoader.shared
        
        // We use a dummy payload URL that will just simulate a network flight
        let testUrlString = "https://example.com/dummy.jpg"
        
        // Clear caches to ensure cold start
        ImageCache.shared.clearCache()
        
        actor TaskCollector {
            var images: [UIImage?] = []
            func add(_ img: UIImage?) { images.append(img) }
        }
        
        let collector = TaskCollector()
        
        // Fire 5 concurrent requests for the exact same URL payload
        await withTaskGroup(of: UIImage?.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    return await loader.loadImage(fromPath: nil, fallbackUrl: testUrlString, maxDimension: 500)
                }
            }
            
            for await result in group {
                await collector.add(result)
            }
        }
        
        let results = await collector.images
        
        // Since it's a dummy URL that will 404/fail, they all should return exactly nil safely.
        // We are just verifying that the internal Task.detached deduplication dictionary allows
        // 5 concurrent requests without blowing up or entering a race condition!
        #expect(results.count == 5)
        
        for result in results {
            #expect(result == nil)
        }
    }
}
