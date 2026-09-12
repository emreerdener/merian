import Foundation
@testable import Merian
import Testing

@Suite("Media Staging Contract")
struct MediaStagingContractTests {
    private struct MediaStagingUploadManifestContract: Decodable {
        let schemaVersion: Int
        let endpoint: String
        let maxFilesPerRequest: Int
        let minFileBytes: Int
        let maxImageBytes: Int
        let maxImageFiles: Int
        let maxAudioBytes: Int
        let maxAudioFiles: Int
        let maxVideoBytes: Int
        let maxVideoFiles: Int
        let imageContentTypes: [String]
        let audioContentTypes: [String]
        let inferenceAudioContentTypes: [String]
        let scanShareRestoreAudioContentTypes: [String]
        let videoContentTypes: [String]
        let canonicalQueuedImageContentType: String
        let canonicalQueuedWavContentType: String
        let canonicalScanShareRestoreM4AContentType: String
        let canonicalInferenceAudioContentType: String
        let audioFileExtensionsByContentType: [String: [String]]
        let canonicalQueuedVideoContentType: String
        let optionalRequestFields: [String]
        let requiredPerFileFields: [String]
        let uploadPurposes: [String]
        let optionalResponseFields: [String]
        let requiredResponseFields: [String]
        let requiredSignedHeaders: [String]
        let signedHeaderSet: String
        let mediaRolesByKind: [String: [String]]
        let fileNamesMustBeUnique: Bool
        let legacyFileNamesAccepted: Bool
    }

    private func loadMediaStagingContract() throws -> MediaStagingUploadManifestContract {
        var searchURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let contractURL = searchURL
                .appendingPathComponent("docs")
                .appendingPathComponent("contracts")
                .appendingPathComponent("media-staging-upload-manifest.json")
            if FileManager.default.fileExists(atPath: contractURL.path) {
                let data = try Data(contentsOf: contractURL)
                return try JSONDecoder().decode(MediaStagingUploadManifestContract.self, from: data)
            }
            searchURL.deleteLastPathComponent()
        }

        throw CocoaError(.fileNoSuchFile)
    }

    @Test func testMediaStagingContractMatchesDocumentedUploadManifestContract() throws {
        let contract = try loadMediaStagingContract()

        #expect(contract.schemaVersion == 6)
        #expect(contract.endpoint == "/generate-upload-urls")
        #expect(MediaStagingContract.maxUploadItemsPerRequest == contract.maxFilesPerRequest)
        #expect(contract.minFileBytes == 1)
        #expect(MediaStagingContract.maxImageItemsPerRequest == contract.maxImageFiles)
        #expect(MediaStagingContract.maxAudioItemsPerRequest == contract.maxAudioFiles)
        #expect(MediaStagingContract.maxVideoItemsPerRequest == contract.maxVideoFiles)
        #expect(ScanMediaPayloadPolicy.maxStagedImageBytes == contract.maxImageBytes)
        #expect(ScanMediaPayloadPolicy.maxInferenceAudioBytes == contract.maxAudioBytes)
        #expect(ScanMediaPayloadPolicy.maxSavedVideoBytes == contract.maxVideoBytes)
        #expect(StagedMediaKind.image.contentType(for: "queued.webp") == contract.canonicalQueuedImageContentType)
        #expect(StagedMediaKind.audio.contentType(for: "queued.wav") == contract.canonicalQueuedWavContentType)
        #expect(
            StagedMediaKind.audio.contentType(for: "queued.m4a") ==
                contract.canonicalScanShareRestoreM4AContentType
        )
        #expect(contract.canonicalInferenceAudioContentType == "audio/wav")
        #expect(StagedMediaKind.video.contentType(for: "queued.mp4") == contract.canonicalQueuedVideoContentType)
        #expect(contract.imageContentTypes.contains(StagedMediaKind.image.contentType(for: "queued.webp")))
        #expect(contract.audioContentTypes.contains(StagedMediaKind.audio.contentType(for: "queued.wav")))
        #expect(contract.audioContentTypes.contains(StagedMediaKind.audio.contentType(for: "queued.m4a")))
        #expect(contract.inferenceAudioContentTypes == ["audio/wav"])
        #expect(contract.scanShareRestoreAudioContentTypes == ["audio/wav", "audio/mp4"])
        #expect(contract.audioFileExtensionsByContentType == [
            "audio/wav": ["wav"],
            "audio/mp4": ["m4a"]
        ])
        #expect(contract.videoContentTypes.contains(StagedMediaKind.video.contentType(for: "queued.mp4")))
        #expect(
            contract.optionalRequestFields ==
                ["clientScanId", "mediaRole", "uploadPurpose"]
        )
        #expect(
            contract.requiredPerFileFields ==
                ["fileName", "mediaKind", "contentType", "sizeBytes"]
        )
        #expect(contract.uploadPurposes == ["scan_share_restore"])
        #expect(contract.optionalResponseFields == ["mediaAssetId", "mediaSessionId"])
        #expect(
            contract.requiredResponseFields ==
                ["fileName", "signedUrl", "objectKey", "requiredHeaders"]
        )
        #expect(contract.requiredSignedHeaders == ["Content-Type", "Content-Length"])
        #expect(contract.signedHeaderSet == "content-length;content-type;host")
        #expect(contract.mediaRolesByKind["image"] == ["display", "thumbnail", "inference_frame"])
        #expect(contract.mediaRolesByKind["audio"] == ["audio"])
        #expect(contract.mediaRolesByKind["video"] == ["playback"])
        #expect(contract.fileNamesMustBeUnique)
        #expect(!contract.legacyFileNamesAccepted)
    }

    @Test func testMediaStagingContractBuildsSanitizedMixedMediaKeys() throws {
        let scanId = "00000000-0000-0000-0000-000000000042"
        let ownerId = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
        let canonicalOwnerId = ownerId.lowercased()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let audioDirectory = directory.appendingPathComponent("field", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data(repeating: 0x21, count: 64).write(to: directory.appendingPathComponent("image one.webp"))
        try makeInferenceTestPCM16WAVData().write(
            to: audioDirectory.appendingPathComponent("audio one.wav")
        )
        try Data(repeating: 0x63, count: 64).write(to: directory.appendingPathComponent("fallback video.mp4"))

        let payload = PendingScanPayload(
            id: scanId,
            localImagePaths: ["image one.webp"],
            localAudioPaths: ["field/audio one.wav"],
            localVideoPaths: ["fallback video.mp4"]
        )

        let items = MediaStagingContract.uploadItems(
            for: payload,
            userId: ownerId,
            documentsDirectory: directory
        )
        #expect(items.count == 3)

        #expect(items[0].mediaKind == StagedMediaKind.image)
        #expect(items[0].fileName == "\(scanId)_image_one.webp")
        #expect(items[0].contentType == "image/webp")
        #expect(items[0].sizeBytes == 64)
        #expect(items[0].objectKey == "staging/\(canonicalOwnerId)/\(scanId)_image_one.webp")

        #expect(items[1].mediaKind == StagedMediaKind.audio)
        #expect(items[1].fileName == "\(scanId)_field_audio_one.wav")
        #expect(items[1].contentType == "audio/wav")
        #expect(items[1].objectKey == "staging/\(canonicalOwnerId)/\(scanId)_field_audio_one.wav")

        #expect(items[2].mediaKind == StagedMediaKind.video)
        #expect(items[2].fileName == "\(scanId)_fallback_video.mp4")
        #expect(items[2].contentType == "video/mp4")
        #expect(items[2].objectKey == "staging/\(canonicalOwnerId)/\(scanId)_fallback_video.mp4")

        let presignedURLs = items.map { item in
            PreSignedURL(
                fileName: item.fileName,
                signedUrl: "https://r2.invalid/bucket/\(item.objectKey)?X-Amz-SignedHeaders=content-length%3Bcontent-type%3Bhost",
                objectKey: item.objectKey,
                requiredHeaders: [
                    "Content-Type": item.contentType,
                    "Content-Length": String(item.sizeBytes)
                ],
                mediaAssetId: nil,
                mediaSessionId: nil
            )
        }
        #expect(
            MediaStagingContract.presignedUploadManifestIsValid(
                uploadItems: items,
                presignedURLs: presignedURLs
            )
        )
        #expect(
            !MediaStagingContract.presignedUploadManifestIsValid(
                uploadItems: items,
                presignedURLs: Array(presignedURLs.dropLast())
            )
        )
        var mixedOwnerURLs = presignedURLs
        mixedOwnerURLs[1] = PreSignedURL(
            fileName: items[1].fileName,
            signedUrl: "https://r2.invalid/bucket/staging/other-owner/\(items[1].fileName)?X-Amz-SignedHeaders=content-length%3Bcontent-type%3Bhost",
            objectKey: "staging/other-owner/\(items[1].fileName)",
            requiredHeaders: presignedURLs[1].requiredHeaders,
            mediaAssetId: nil,
            mediaSessionId: nil
        )
        #expect(
            !MediaStagingContract.presignedUploadManifestIsValid(
                uploadItems: items,
                presignedURLs: mixedOwnerURLs
            )
        )
        let replacementOwnerId = UUID().uuidString.lowercased()
        let replacementOwnerURLs = items.map { item in
            let replacementObjectKey = MediaStagingContract.objectKey(
                userId: replacementOwnerId,
                fileName: item.fileName
            )
            return PreSignedURL(
                fileName: item.fileName,
                signedUrl: "https://r2.invalid/bucket/\(replacementObjectKey)?X-Amz-SignedHeaders=content-length%3Bcontent-type%3Bhost",
                objectKey: replacementObjectKey,
                requiredHeaders: [
                    "Content-Type": item.contentType,
                    "Content-Length": String(item.sizeBytes)
                ],
                mediaAssetId: nil,
                mediaSessionId: nil
            )
        }
        #expect(
            !MediaStagingContract.presignedUploadManifestIsValid(
                uploadItems: items,
                presignedURLs: replacementOwnerURLs
            )
        )
        var mixedOriginURLs = presignedURLs
        mixedOriginURLs[1] = PreSignedURL(
            fileName: items[1].fileName,
            signedUrl: "https://other-r2.invalid/bucket/\(items[1].objectKey)?X-Amz-SignedHeaders=content-length%3Bcontent-type%3Bhost",
            objectKey: items[1].objectKey,
            requiredHeaders: presignedURLs[1].requiredHeaders,
            mediaAssetId: nil,
            mediaSessionId: nil
        )
        #expect(
            !MediaStagingContract.presignedUploadManifestIsValid(
                uploadItems: items,
                presignedURLs: mixedOriginURLs
            )
        )
        var insecureURLs = presignedURLs
        insecureURLs[0] = PreSignedURL(
            fileName: items[0].fileName,
            signedUrl: "http://r2.invalid/bucket/\(items[0].objectKey)?X-Amz-SignedHeaders=content-length%3Bcontent-type%3Bhost",
            objectKey: items[0].objectKey,
            requiredHeaders: presignedURLs[0].requiredHeaders,
            mediaAssetId: nil,
            mediaSessionId: nil
        )
        #expect(
            !MediaStagingContract.presignedUploadManifestIsValid(
                uploadItems: items,
                presignedURLs: insecureURLs
            )
        )
        var wrongSizeURLs = presignedURLs
        wrongSizeURLs[0] = PreSignedURL(
            fileName: items[0].fileName,
            signedUrl: presignedURLs[0].signedUrl,
            objectKey: items[0].objectKey,
            requiredHeaders: [
                "Content-Type": items[0].contentType,
                "Content-Length": "65"
            ],
            mediaAssetId: nil,
            mediaSessionId: nil
        )
        #expect(
            !MediaStagingContract.presignedUploadManifestIsValid(
                uploadItems: items,
                presignedURLs: wrongSizeURLs
            )
        )
        #expect(
            !MediaStagingContract.presignedUploadManifestIsValid(
                uploadItems: [items[0], items[0]],
                presignedURLs: [presignedURLs[0], presignedURLs[0]]
            )
        )

        let uploadFiles = try MediaStagingContract.uploadFiles(for: items)
        #expect(uploadFiles.map(\.clientScanId) == Array(repeating: Optional(payload.id), count: 3))
        #expect(uploadFiles.map(\.mediaRole) == ["display", "audio", "playback"])

        let splitKeys = MediaStagingContract.splitObjectKeys(
            items.map(\.objectKey),
            scanId: payload.id,
            localImagePaths: payload.localImagePaths,
            localAudioPaths: payload.localAudioPaths,
            localVideoPaths: payload.localVideoPaths
        )
        #expect(splitKeys.imageR2ObjectKeys == [items[0].objectKey])
        #expect(splitKeys.audioR2ObjectKeys == [items[1].objectKey])
        #expect(splitKeys.videoR2ObjectKeys == [items[2].objectKey])

        try Data(repeating: 0x99, count: 65).write(
            to: directory.appendingPathComponent("image one.webp")
        )
        #expect(!MediaStagingContract.fileSizeMatchesSigningSnapshot(items[0]))
    }

    @Test func testMediaStagingUploadTaskDescriptionPreservesUnderscoredScanIds() {
        let scanId = "queued_nonvisual_audio_only"
        let syncGeneration = UUID()
        let ownerId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let objectKey = "staging/\(ownerId)/\(scanId)_audio.wav"
        let description = MediaStagingContract.uploadTaskDescription(
            scanId: scanId,
            uploadIndex: 12,
            syncGeneration: syncGeneration,
            objectKey: objectKey,
            ownerUserID: UUID(uuidString: ownerId)!
        )
        let identity = MediaStagingContract.parseUploadTaskDescription(description)

        #expect(identity?.scanId == scanId)
        #expect(identity?.uploadIndex == 12)
        #expect(identity?.syncGeneration == syncGeneration)
        #expect(identity?.objectKey == objectKey)
        #expect(identity?.ownerUserID?.uuidString.lowercased() == ownerId)
        #expect(MediaStagingContract.uploadTaskDescription(description, belongsTo: scanId))
    }

    @Test func testMediaStagingContractAcceptsAuthenticatedCanonicalKeyAfterIdentityChanges() {
        let fileName = "scan-42_image.webp"
        let authenticatedOwnerId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        let authenticatedKey = "staging/\(authenticatedOwnerId)/\(fileName)"
        let signedPath = "/merian-media/staging/\(authenticatedOwnerId)/\(fileName)"

        #expect(MediaStagingContract.isCanonicalObjectKey(
            authenticatedKey,
            fileName: fileName
        ))
        #expect(
            MediaStagingContract.objectKey(fromPresignedURLPath: signedPath)
                == authenticatedKey
        )
        #expect(
            MediaStagingContract.ownerId(fromObjectKey: authenticatedKey)
                == authenticatedOwnerId
        )
        #expect(!MediaStagingContract.isCanonicalObjectKey(
            "staging/cccccccc-cccc-4ccc-8ccc-cccccccccccc/other-file.webp",
            fileName: fileName
        ))
        #expect(!MediaStagingContract.isCanonicalObjectKey(
            "staging/not-a-uuid/\(fileName)",
            fileName: fileName
        ))
        #expect(
            MediaStagingContract.objectKey(
                fromPresignedURLPath:
                    "/merian-media/staging/\(authenticatedOwnerId)/../\(fileName)"
            ) == nil
        )
    }

    @Test func testMediaStagingOwnerResolutionPrefersPersistedAuthSession() {
        let sessionUserId = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
        let hydratedUserId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        let deviceId = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"

        #expect(
            MediaStagingContract.preferredOwnerId(
                sessionUserId: sessionUserId,
                hydratedUserId: hydratedUserId,
                deviceId: deviceId
            ) == sessionUserId.lowercased()
        )
        #expect(
            MediaStagingContract.preferredOwnerId(
                sessionUserId: nil,
                hydratedUserId: hydratedUserId,
                deviceId: deviceId
            ) == hydratedUserId
        )
        #expect(
            MediaStagingContract.preferredOwnerId(
                sessionUserId: nil,
                hydratedUserId: nil,
                deviceId: deviceId
            ) == deviceId
        )
    }

}
