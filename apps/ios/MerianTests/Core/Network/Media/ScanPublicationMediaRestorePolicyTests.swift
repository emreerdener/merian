import Foundation
import Testing

@testable import Merian

@Suite("Scan Publication Media Restore")
struct ScanPublicationMediaRestorePolicyTests {
    @Test func restoreEligibilityPreservesEndpointFailureClassification() {
        let videoOwnership = MerianError.httpError(
            statusCode: 400,
            message: "Selected video media does not belong to this scan."
        )
        let audioOwnership = MerianError.httpError(
            statusCode: 400,
            message: "Selected audio media does not belong to this scan."
        )
        for error in [videoOwnership, audioOwnership] {
            #expect(
                ScanPublicationMediaRestorePolicy.shouldAttemptRestore(
                    after: error
                )
            )
            #expect(
                !ScanPublicationMediaRestorePolicy.shouldRestoreImages(
                    after: error
                )
            )
        }

        for message in [
            "This scan no longer has shareable image media.",
            "This scan no longer has shareable media.",
            "Video thumbnail unavailable."
        ] {
            let error = MerianError.httpError(statusCode: 409, message: message)
            #expect(
                ScanPublicationMediaRestorePolicy.shouldAttemptRestore(
                    after: error
                )
            )
            #expect(
                ScanPublicationMediaRestorePolicy.shouldRestoreImages(
                    after: error
                )
            )
        }

        for error in [
            MerianError.httpError(statusCode: 400, message: "Other rejection"),
            MerianError.httpError(statusCode: 409, message: "Other conflict"),
            MerianError.httpError(
                statusCode: 404,
                message: "This scan no longer has shareable media."
            ),
            MerianError.invalidResponse
        ] {
            #expect(
                !ScanPublicationMediaRestorePolicy.shouldAttemptRestore(
                    after: error
                )
            )
            #expect(
                ScanPublicationMediaRestorePolicy.shouldRestoreImages(
                    after: error
                )
            )
        }
    }

    @Test func testExploreRestoreMediaBudgetRejectsPartialStagingBeforeUpload() throws {
        try ScanPublicationMediaRestorePolicy.validatePayload(
            imageSizes: [1, 2, 3],
            videoSizes: [MerianConfig.videoPayloadMaxBytes],
            audioSizes: [1, MerianConfig.audioPayloadMaxBytes]
        )
        try ScanPublicationMediaRestorePolicy.validateBudget(
            imageCount: 5,
            videoCount: 1,
            audioCount: 0
        )

        for counts in [
            (image: -1, video: 0, audio: 0),
            (image: 6, video: 0, audio: 0),
            (image: 0, video: 2, audio: 0),
            (image: 0, video: 0, audio: 3),
            (image: 5, video: 0, audio: 2)
        ] {
            #expect(throws: MerianError.payloadTooLarge) {
                try ScanPublicationMediaRestorePolicy.validateBudget(
                    imageCount: counts.image,
                    videoCount: counts.video,
                    audioCount: counts.audio
                )
            }
        }

        for sizes in [
            (images: [-1], videos: [Int](), audio: [Int]()),
            (images: [0], videos: [Int](), audio: [Int]()),
            (
                images: [MerianConfig.stagedImagePayloadMaxBytes, 1],
                videos: [Int](),
                audio: [Int]()
            ),
            (images: [Int](), videos: [0], audio: [Int]()),
            (
                images: [Int](),
                videos: [MerianConfig.videoPayloadMaxBytes + 1],
                audio: [Int]()
            ),
            (images: [Int](), videos: [Int](), audio: [0]),
            (
                images: [Int](),
                videos: [Int](),
                audio: [MerianConfig.audioPayloadMaxBytes + 1]
            )
        ] {
            #expect(throws: MerianError.payloadTooLarge) {
                try ScanPublicationMediaRestorePolicy.validatePayload(
                    imageSizes: sizes.images,
                    videoSizes: sizes.videos,
                    audioSizes: sizes.audio
                )
            }
        }

        let scanId = "019f7004-d6c4-7da1-8561-9cc101f6db62"
        for (kind, fileName, expectedRole) in [
            (
                StagedMediaKind.image,
                "\(scanId)_explore_restore_0.webp",
                "display"
            ),
            (
                StagedMediaKind.video,
                "\(scanId)_explore_restore_video_0.mp4",
                "playback"
            ),
            (
                StagedMediaKind.audio,
                "\(scanId)_explore_restore_audio_0.wav",
                "audio"
            )
        ] {
            let uploadFile = ScanPublicationMediaRestorePolicy.makeUploadFile(
                fileName: fileName,
                mediaKind: kind,
                contentType: kind.contentType(for: fileName),
                sizeBytes: 42,
                scanId: scanId
            )
            #expect(uploadFile.clientScanId == scanId)
            #expect(uploadFile.mediaRole == expectedRole)
            #expect(uploadFile.uploadPurpose == .scanShareRestore)
            let encoded = try JSONEncoder().encode(uploadFile)
            let payload = try #require(
                JSONSerialization.jsonObject(with: encoded) as? [String: Any]
            )
            #expect(
                payload["uploadPurpose"] as? String
                    == StagingUploadPurpose.scanShareRestore.rawValue
            )
        }
    }
}
