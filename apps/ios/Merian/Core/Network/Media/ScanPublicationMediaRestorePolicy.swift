import Foundation

enum ScanPublicationMediaRestorePolicy {
    static func shouldAttemptRestore(after error: Error) -> Bool {
        guard case let MerianError.httpError(statusCode, message) = error else {
            return false
        }

        if statusCode == 400 {
            return message.contains("Selected video media does not belong to this scan.")
                || message.contains("Selected audio media does not belong to this scan.")
        }

        guard statusCode == 409 else {
            return false
        }

        return message.contains("This scan no longer has shareable image media.")
            || message.contains("This scan no longer has shareable media.")
            || message.contains("Video thumbnail unavailable.")
    }

    static func shouldRestoreImages(after error: Error) -> Bool {
        guard case let MerianError.httpError(statusCode, message) = error else {
            return true
        }

        return !(statusCode == 400 && (
            message.contains("Selected video media does not belong to this scan.")
                || message.contains("Selected audio media does not belong to this scan.")
        ))
    }

    static func validateBudget(
        imageCount: Int,
        videoCount: Int,
        audioCount: Int
    ) throws {
        guard imageCount >= 0,
              videoCount >= 0,
              audioCount >= 0,
              imageCount <= MerianConfig.mediaStagingMaxImageFilesPerRequest,
              videoCount <= MerianConfig.mediaStagingMaxVideoFilesPerRequest,
              audioCount <= MerianConfig.mediaStagingMaxAudioFilesPerRequest,
              imageCount + videoCount + audioCount
                <= MerianConfig.mediaStagingMaxFilesPerRequest else {
            throw MerianError.payloadTooLarge
        }
    }

    static func validatePayload(
        imageSizes: [Int],
        videoSizes: [Int],
        audioSizes: [Int]
    ) throws {
        try validateBudget(
            imageCount: imageSizes.count,
            videoCount: videoSizes.count,
            audioCount: audioSizes.count
        )

        var totalImageBytes = 0
        for sizeBytes in imageSizes {
            let addition = totalImageBytes.addingReportingOverflow(sizeBytes)
            guard sizeBytes > 0,
                  !addition.overflow,
                  addition.partialValue <= MerianConfig.stagedImagePayloadMaxBytes else {
                throw MerianError.payloadTooLarge
            }
            totalImageBytes = addition.partialValue
        }
        guard videoSizes.allSatisfy({
            $0 > 0 && $0 <= MerianConfig.videoPayloadMaxBytes
        }),
        audioSizes.allSatisfy({
            $0 > 0 && $0 <= MerianConfig.audioPayloadMaxBytes
        }) else {
            throw MerianError.payloadTooLarge
        }
    }

    static func makeUploadFile(
        fileName: String,
        mediaKind: StagedMediaKind,
        contentType: String,
        sizeBytes: Int,
        scanId: String
    ) -> StagingUploadFile {
        StagingUploadFile(
            fileName: fileName,
            mediaKind: mediaKind,
            contentType: contentType,
            sizeBytes: sizeBytes,
            clientScanId: scanId,
            mediaRole: mediaKind.defaultScanMediaRole,
            uploadPurpose: .scanShareRestore
        )
    }
}
