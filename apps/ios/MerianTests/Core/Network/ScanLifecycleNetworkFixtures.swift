import Foundation

@testable import Merian

enum ScanLifecycleNetworkFixtures {
    static let scanID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    static let secondScanID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    static let userID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    static let statusJSON = #"{"status":"found"}"#
    static let deletionJSON = #"{"success":true,"message":"Synthetic confirmation"}"#
    static let bulkJSON = #"{"results":[{"scan_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","status":"found"}]}"#
    static let detailedStatusJSON = """
    {
      "scan_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      "status":"not_found",
      "job_status":"finalizing",
      "job_stage":"video_promotion_started",
      "job_attempt_count":2,
      "retry_after":"2026-09-01T12:00:00Z",
      "last_error":"Synthetic retry detail",
      "complimentary_state":"held"
    }
    """
    static let recoveryJSON = """
    {
      "id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      "user_id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc",
      "image_storage_urls":[],
      "timestamp":"2026-09-01T12:00:00Z",
      "geoprivacy":"private",
      "ai_confidence_score":0.75,
      "ecology_type":"wild",
      "is_invasive":false,
      "is_live_capture":true,
      "is_biological_subject":true,
      "inference_tier":"flash",
      "image_quality_score":0,
      "user_confirmed_identification":false,
      "user_review_state":"unreviewed"
    }
    """

    static func recoveryScan(confidence: Double = 0.75) -> OwnedScanRecoveryPayload {
        OwnedScanRecoveryPayload(
            id: scanID, userId: userID, speciesId: nil, confirmedSpeciesId: nil,
            imageStorageUrls: [], timestamp: "2026-09-01T12:00:00Z",
            gpsLatExact: nil, gpsLongExact: nil, gpsLatPublic: nil, gpsLongPublic: nil,
            gpsElevation: nil, geoprivacy: "private", weatherCondition: nil,
            weatherTemperatureF: nil, aiConfidenceScore: confidence, ecologyType: "wild",
            isInvasive: false, invasiveStatusRegion: nil, invasiveRationale: nil,
            invasiveConfidence: nil, isLiveCapture: true, isBiologicalSubject: true,
            aiReasoning: nil, semanticLocation: nil, publicLocationLabel: nil,
            inferenceTier: "flash", imageQualityScore: 0, userIdentificationOverride: nil,
            userConfirmedIdentification: false, userReviewState: "unreviewed"
        )
    }
}
