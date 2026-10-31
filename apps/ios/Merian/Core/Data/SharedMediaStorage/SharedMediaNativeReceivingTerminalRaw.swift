import Foundation
import SwiftData

/// Complete persisted quartet fields, including nils and the empty relationship.
/// These values are ephemeral write seals, never diagnostics or retained evidence.
@MainActor
enum SharedMediaNativeReceivingTerminalRaw {
    typealias Fields = SharedMediaNativeReleasePairRaw.Fields
    private static func value<T: Encodable>(_ value: T) throws -> Data {
        try SharedMediaNativeReleasePairRaw.value(value)
    }
    static func fields(_ row: SharedMediaConsumerRecord) throws -> Fields {
        return try [
            "id": value(row.id),
            "cursorKey": value(row.cursorKey),
            "kindRaw": value(row.kindRaw),
            "consumerID": value(row.consumerID),
            "originQueueID": value(row.originQueueID),
            "observationID": value(row.observationID),
            "inventoryID": value(row.inventoryID),
            "inventoryGeneration": value(row.inventoryGeneration),
            "ownerID": value(row.ownerID),
            "packageID": value(row.packageID),
            "draftGeneration": value(row.draftGeneration),
            "frozenPackageRevision": value(row.frozenPackageRevision),
            "contractVersion": value(row.contractVersion),
            "digestVersion": value(row.digestVersion),
            "cohortData": value(row.cohortData),
            "cohortSHA256": value(row.cohortSHA256),
            "executionKindRaw": value(row.executionKindRaw),
            "inferenceGeneration": value(row.inferenceGeneration),
            "retirementID": value(row.retirementID),
            "lifecycleRaw": value(row.lifecycleRaw),
            "revision": value(row.revision)
        ]
    }
    static func fields(_ row: OfflineQueuedScan) throws -> Fields {
        guard row.capturedMediaEntries?.isEmpty != false else { throw SharedMediaStorageFailure.conflict }
        return try [
            "mediaAuthorityRaw": value(row.mediaAuthorityRaw),
            "sharedMediaConsumerID": value(row.sharedMediaConsumerID),
            "id": value(row.id),
            "workKindRaw": value(row.workKindRaw),
            "parentObservationID": value(row.parentObservationID),
            "sourceAnalysisID": value(row.sourceAnalysisID),
            "reanalysisOwnerAccountID": value(row.reanalysisOwnerAccountID),
            "timestamp": value(row.timestamp),
            "recoveryPresentationData": value(row.recoveryPresentationData),
            "capturedMediaJSON": value(row.capturedMediaJSON),
            "capturedMediaEntries": value(row.capturedMediaEntries.map { $0.map(\.persistentModelID) }),
            "gpsLatitude": value(row.gpsLatitude),
            "gpsLongitude": value(row.gpsLongitude),
            "gpsElevation": value(row.gpsElevation),
            "weatherCondition": value(row.weatherCondition),
            "weatherTemperatureF": value(row.weatherTemperatureF),
            "blurScore": value(row.blurScore),
            "subjectDistanceInMeters": value(row.subjectDistanceInMeters),
            "locationName": value(row.locationName),
            "isFlashFired": value(row.isFlashFired),
            "cameraPitchDegrees": value(row.cameraPitchDegrees),
            "compassHeading": value(row.compassHeading),
            "relativeHumidity": value(row.relativeHumidity),
            "uvIndex": value(row.uvIndex),
            "zoomFactor": value(row.zoomFactor),
            "scanStateRaw": value(row.scanStateRaw),
            "stagedR2Keys": value(row.stagedR2Keys),
            "inferenceImagePaths": value(row.inferenceImagePaths),
            "visualMediaItemsJSON": value(row.visualMediaItemsJSON),
            "fieldNotes": value(row.fieldNotes),
            "queueAttemptCount": value(row.queueAttemptCount),
            "queueLastAttemptAt": value(row.queueLastAttemptAt),
            "queueNextRetryAt": value(row.queueNextRetryAt),
            "queueLastErrorCode": value(row.queueLastErrorCode),
            "queueLastErrorMessage": value(row.queueLastErrorMessage),
            "queueLastHTTPStatus": value(row.queueLastHTTPStatus),
            "queueLastServerStatus": value(row.queueLastServerStatus),
            "queueLastServerStage": value(row.queueLastServerStage),
            "queueLastServerRetryAfter": value(row.queueLastServerRetryAfter),
            "queueUpdatedAt": value(row.queueUpdatedAt),
            "queueNeedsAttention": value(row.queueNeedsAttention),
            "queueSchemaRepairGeneration": value(row.queueSchemaRepairGeneration),
            "coverImagePath": value(row.coverImagePath)
        ]
    }
    static func fields(_ row: OfflineJobRecord) throws -> Fields {
        return try [
            "id": value(row.id),
            "kindRaw": value(row.kindRaw),
            "subjectId": value(row.subjectId),
            "priority": value(row.priority),
            "statusRaw": value(row.statusRaw),
            "createdAt": value(row.createdAt),
            "updatedAt": value(row.updatedAt),
            "lastAttemptAt": value(row.lastAttemptAt),
            "nextRunAt": value(row.nextRunAt),
            "attemptCount": value(row.attemptCount),
            "lastErrorCode": value(row.lastErrorCode),
            "lastErrorMessage": value(row.lastErrorMessage),
            "lastHTTPStatus": value(row.lastHTTPStatus),
            "serverStatus": value(row.serverStatus),
            "serverStage": value(row.serverStage),
            "serverRetryAfter": value(row.serverRetryAfter),
            "requiresUnconstrainedNetwork": value(row.requiresUnconstrainedNetwork),
            "allowsCellular": value(row.allowsCellular),
            "approximateBytes": value(row.approximateBytes),
            "metadataJSON": value(row.metadataJSON)
        ]
    }
    static func fields(_ row: OfflineQueueEvent) throws -> Fields {
        return try [
            "id": value(row.id),
            "jobId": value(row.jobId),
            "scanId": value(row.scanId),
            "kindRaw": value(row.kindRaw),
            "createdAt": value(row.createdAt),
            "message": value(row.message),
            "errorCode": value(row.errorCode),
            "httpStatus": value(row.httpStatus),
            "metadataJSON": value(row.metadataJSON)
        ]
    }
}
