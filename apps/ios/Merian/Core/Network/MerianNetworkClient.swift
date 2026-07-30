import CryptoKit
import Foundation
import os

// Using MerianError from Core/Utilities.

// MARK: - Pre-Signed URL DTOs

struct PreSignedURLResponse: Codable {
    let urls: [PreSignedURL]
}

struct PreSignedURL: Codable {
    let fileName: String
    let signedUrl: String
    let objectKey: String
    let mediaAssetId: String?
    let mediaSessionId: String?
}

enum ScanImageCloudStatus: String, Decodable, Equatable, Sendable {
    case healthy
    case missing
    case notReferenced = "not_referenced"
    case repaired
}

struct ScanImageCloudInspection: Decodable, Equatable, Sendable {
    let status: ScanImageCloudStatus
    let replacementUrl: String?
    let updatedScanCount: Int
    let updatedPostMediaCount: Int

    private enum CodingKeys: String, CodingKey {
        case status
        case replacementUrl = "replacement_url"
        case updatedScanCount = "updated_scan_count"
        case updatedPostMediaCount = "updated_post_media_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(ScanImageCloudStatus.self, forKey: .status)
        replacementUrl = try container.decodeIfPresent(String.self, forKey: .replacementUrl)
        updatedScanCount = try container.decodeIfPresent(Int.self, forKey: .updatedScanCount) ?? 0
        updatedPostMediaCount = try container.decodeIfPresent(Int.self, forKey: .updatedPostMediaCount) ?? 0
    }
}

private struct ScanImageCloudInspectionResponse: Decodable {
    let data: ScanImageCloudInspection
}

enum ScanCloudStatus: String, Decodable, Equatable, Sendable {
    case found
    case notFound = "not_found"
}

enum ScanIngestionJobStatus: String, Decodable, Equatable, Sendable {
    case processing
    case finalizing
    case retrying
    case failedRetryable = "failed_retryable"
    case failed
    case complete

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if rawValue == "failed_terminal" {
            self = .failed
            return
        }
        guard let status = ScanIngestionJobStatus(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown scan ingestion job status: \(rawValue)"
            )
        }
        self = status
    }
}

struct ScanStatusResponse: Decodable, Equatable, Sendable {
    let scanId: String?
    let status: ScanCloudStatus
    let jobStatus: ScanIngestionJobStatus?
    let jobStage: String?
    let jobAttemptCount: Int?
    let retryAfter: String?
    let lastError: String?

    var isFound: Bool { status == .found }

    init(
        scanId: String? = nil,
        status: ScanCloudStatus,
        jobStatus: ScanIngestionJobStatus?,
        jobStage: String?,
        jobAttemptCount: Int?,
        retryAfter: String?,
        lastError: String?
    ) {
        self.scanId = scanId
        self.status = status
        self.jobStatus = jobStatus
        self.jobStage = jobStage
        self.jobAttemptCount = jobAttemptCount
        self.retryAfter = retryAfter
        self.lastError = lastError
    }

    private enum CodingKeys: String, CodingKey {
        case scanId = "scan_id"
        case status
        case jobStatus = "job_status"
        case jobStage = "job_stage"
        case jobAttemptCount = "job_attempt_count"
        case retryAfter = "retry_after"
        case lastError = "last_error"
    }
}

enum MissingScanRecoveryAction: Equatable, Sendable {
    case retryStatus
    case recover
    case deferRecovery
}

func missingScanRecoveryAction(
    for jobStatus: ScanIngestionJobStatus?,
    jobStage: String? = nil,
    jobLastError: String? = nil
) -> MissingScanRecoveryAction {
    let normalizedStage = jobStage?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    let normalizedError = jobLastError?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    let isModerationRejection = normalizedStage == "moderation_rejected"
        && (
            normalizedError == "multimodal media rejected by moderation."
                || normalizedError == "media rejected by moderation."
        )
    let isProviderPolicyRejection = normalizedStage == "ai_inference_non_stop_finish"
        && (
            normalizedError == "ai finish reason: safety"
                || normalizedError == "ai finish reason: prohibited_content"
        )
    if isModerationRejection || isProviderPolicyRejection {
        return .deferRecovery
    }

    switch jobStatus {
    case .processing?, .finalizing?, .retrying?:
        return .retryStatus
    case .failedRetryable?:
        return .deferRecovery
    case .failed?, .complete?, nil:
        return .recover
    }
}

private struct BulkScanStatusResponse: Decodable {
    let results: [ScanStatusResponse]
}

private struct DeleteScanResponse: Decodable {
    let success: Bool
}

private struct UploadURLRequestBody: Encodable {
    let files: [StagingUploadFile]
    let userId: String

    private enum CodingKeys: String, CodingKey {
        case files
        case userId = "user_id"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct ExploreShareMediaSnapshot {
    let scanId: String
    let imagePaths: [String]
    let videoPaths: [String]
    let audioPaths: [String]
    let coverImagePath: String?
    let fallbackImageData: Data?
    let scientificName: String
    let commonName: String
    let timestamp: Date
    let captureDate: Date?
    let gpsLatitude: Double?
    let gpsLongitude: Double?
    let gpsElevation: Double?
    let locationName: String?
    let weatherCondition: String?
    let weatherTemperatureF: Double?
    let confidenceScore: Double?
    let isBiological: Bool
    let isLiveCapture: Bool
    let isInvasive: Bool
    let invasiveStatusRegion: String?
    let invasiveRationale: String?
    let invasiveConfidence: Double?
    let ecologyType: String
    let aiReasoning: String?
    let inferenceTier: String?
    let imageQualityScore: Int?
    let confirmedSpeciesId: String?
    let userIdentificationOverride: String?
    let userConfirmedIdentification: Bool
    let userReviewStateRaw: String?

    init(scan: LocalScanRecord, fallbackImageData: Data? = nil) {
        self.scanId = scan.id
        let mediaSnapshot = scan.capturedMediaSnapshot
        self.imagePaths = mediaSnapshot.thumbnailImagePaths
        self.videoPaths = mediaSnapshot.videoPaths
        self.audioPaths = mediaSnapshot.audioPaths
        self.coverImagePath = scan.coverImagePath
        self.fallbackImageData = fallbackImageData
        self.scientificName = scan.scientificName
        self.commonName = scan.commonName
        self.timestamp = scan.timestamp
        self.captureDate = scan.captureDate
        self.gpsLatitude = scan.gpsLatitude
        self.gpsLongitude = scan.gpsLongitude
        self.gpsElevation = scan.gpsElevation
        self.locationName = scan.locationName
        self.weatherCondition = scan.weatherCondition
        self.weatherTemperatureF = scan.weatherTemperatureF
        self.confidenceScore = scan.confidenceScore
        self.isBiological = scan.isBiological
        self.isLiveCapture = scan.isLiveCapture
        self.isInvasive = scan.isInvasive
        self.invasiveStatusRegion = scan.invasiveStatusRegion
        self.invasiveRationale = scan.invasiveRationale
        self.invasiveConfidence = scan.invasiveConfidence
        self.ecologyType = scan.ecologyType
        self.aiReasoning = scan.aiReasoning
        self.inferenceTier = scan.inferenceTier
        self.imageQualityScore = scan.imageQualityScore
        self.confirmedSpeciesId = scan.confirmedSpeciesId
        self.userIdentificationOverride = scan.userIdentificationOverride
        self.userConfirmedIdentification = scan.userConfirmedIdentification
        self.userReviewStateRaw = scan.userReviewStateRaw
    }
}

private struct ExploreRestoreMediaObjectKeys {
    let imageObjectKeys: [String]
    let videoObjectKeys: [String]
    let audioObjectKeys: [String]

    var isEmpty: Bool {
        imageObjectKeys.isEmpty && videoObjectKeys.isEmpty && audioObjectKeys.isEmpty
    }
}

func validateExploreRestoreMediaBudget(
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

func validateExploreRestoreMediaPayload(
    imageSizes: [Int],
    videoSizes: [Int],
    audioSizes: [Int]
) throws {
    try validateExploreRestoreMediaBudget(
        imageCount: imageSizes.count,
        videoCount: videoSizes.count,
        audioCount: audioSizes.count
    )

    var totalImageBytes = 0
    for sizeBytes in imageSizes {
        let addition = totalImageBytes.addingReportingOverflow(sizeBytes)
        guard sizeBytes >= 0,
              !addition.overflow,
              addition.partialValue <= MerianConfig.stagedImagePayloadMaxBytes else {
            throw MerianError.payloadTooLarge
        }
        totalImageBytes = addition.partialValue
    }
    guard videoSizes.allSatisfy({
        $0 >= 0 && $0 <= MerianConfig.videoPayloadMaxBytes
    }),
    audioSizes.allSatisfy({
        $0 >= 0 && $0 <= MerianConfig.audioPayloadMaxBytes
    }) else {
        throw MerianError.payloadTooLarge
    }
}

func makeScanShareRestoreUploadFile(
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

private enum ScanPersistenceProbeResult {
    case found
    case recoverableMissing
    case deferRecovery
    case serviceUnavailable
}

struct OwnedScanRecoveryPayload: Encodable, Sendable {
    let id: String
    let userId: String
    let speciesId: String?
    let confirmedSpeciesId: String?
    let imageStorageUrls: [String]
    let timestamp: String
    let gpsLatExact: Double?
    let gpsLongExact: Double?
    let gpsLatPublic: Double?
    let gpsLongPublic: Double?
    let gpsElevation: Double?
    let geoprivacy: String
    let weatherCondition: String?
    let weatherTemperatureF: Double?
    let aiConfidenceScore: Double
    let ecologyType: String
    let isInvasive: Bool
    let invasiveStatusRegion: String?
    let invasiveRationale: String?
    let invasiveConfidence: Double?
    let isLiveCapture: Bool
    let isBiologicalSubject: Bool
    let aiReasoning: String?
    let semanticLocation: String?
    let publicLocationLabel: String?
    let inferenceTier: String
    let imageQualityScore: Int?
    let userIdentificationOverride: String?
    let userConfirmedIdentification: Bool
    let userReviewState: String

    private enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case speciesId = "species_id"
        case confirmedSpeciesId = "confirmed_species_id"
        case imageStorageUrls = "image_storage_urls"
        case timestamp
        case gpsLatExact = "gps_lat_exact"
        case gpsLongExact = "gps_long_exact"
        case gpsLatPublic = "gps_lat_public"
        case gpsLongPublic = "gps_long_public"
        case gpsElevation = "gps_elevation"
        case geoprivacy
        case weatherCondition = "weather_condition"
        case weatherTemperatureF = "weather_temperature_f"
        case aiConfidenceScore = "ai_confidence_score"
        case ecologyType = "ecology_type"
        case isInvasive = "is_invasive"
        case invasiveStatusRegion = "invasive_status_region"
        case invasiveRationale = "invasive_rationale"
        case invasiveConfidence = "invasive_confidence"
        case isLiveCapture = "is_live_capture"
        case isBiologicalSubject = "is_biological_subject"
        case aiReasoning = "ai_reasoning"
        case semanticLocation = "semantic_location"
        case publicLocationLabel = "public_location_label"
        case inferenceTier = "inference_tier"
        case imageQualityScore = "image_quality_score"
        case userIdentificationOverride = "user_identification_override"
        case userConfirmedIdentification = "user_confirmed_identification"
        case userReviewState = "user_review_state"
    }
}

private struct ExploreCloudSpeciesIdRow: Decodable {
    let id: String
}

private struct EdgeErrorPayload: Decodable {
    let code: String?
    let error: String?
    let message: String?
}

struct EdgeFunctionRouteResponseEvidence: Sendable {
    let statusCode: Int
    let handlerMarker: String?
    let supabaseErrorCode: String?
    let hasGatewayVersion: Bool
    let hasExecutionId: Bool
    let retryAfterSeconds: TimeInterval?

    init(response: HTTPURLResponse) {
        statusCode = response.statusCode
        handlerMarker = response.value(forHTTPHeaderField: "X-Merian-Handler")
        supabaseErrorCode = response.value(forHTTPHeaderField: "SB-Error-Code")
        hasGatewayVersion = response.value(forHTTPHeaderField: "SB-Gateway-Version") != nil
        hasExecutionId = response.value(forHTTPHeaderField: "X-Deno-Execution-Id") != nil
        retryAfterSeconds = response.value(forHTTPHeaderField: "Retry-After")
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .flatMap { (1...86_400).contains($0) ? TimeInterval($0) : nil }
    }
}

private struct InferenceRequestContext: Sendable {
    let userId: String
    let deviceLocale: String
    let deviceTimeZone: String
    let deviceRegion: String?
    let currentMonth: Int
    let timeOfDay: String
    let depthScaleText: String?
    let defaultGeoprivacy: String
}

private enum InferencePayloadBuilder {
    static func makeContext(
        userId: String,
        telemetry: CaptureTelemetry,
        defaultGeoprivacy: String
    ) -> InferenceRequestContext {
        let captureDate: Date = telemetry.timestamp.flatMap {
            DateUtilities.iso8601Formatter.date(from: $0)
        } ?? Date()

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        return InferenceRequestContext(
            userId: userId.lowercased(),
            deviceLocale: Locale.current.language.languageCode?.identifier ?? "en",
            deviceTimeZone: TimeZone.current.identifier,
            deviceRegion: Locale.current.region?.identifier,
            currentMonth: Calendar.current.component(.month, from: captureDate),
            timeOfDay: formatter.string(from: captureDate),
            depthScaleText: telemetry.subjectDistanceInMeters.map { String(format: "%.1f meters", $0) },
            defaultGeoprivacy: normalizedGeoprivacy(defaultGeoprivacy)
        )
    }

    static func identifyBody(
        r2ObjectKeys: [String]?,
        imageBase64s: [String]?,
        mimeType: String,
        telemetry: CaptureTelemetry,
        context: InferenceRequestContext,
        clientScanId: String?,
        description: String?,
        observationContextJSON: String?
    ) throws -> Data {
        try MerianNetworkClient.validateMultiModalPayloadBudget(
            imageBase64s: imageBase64s ?? [],
            audioBase64s: []
        )

        var payload = telemetryPayloadFields(
            telemetry: telemetry,
            context: context,
            clientScanId: clientScanId
        )
        setIfPresent(r2ObjectKeys, forKey: "r2ObjectKeys", in: &payload)
        setIfPresent(imageBase64s, forKey: "imageBase64s", in: &payload)
        payload["mimeType"] = mimeType

        if let description, !description.isEmpty {
            payload["description"] = description
        }

        setIfPresent(
            observationContextObject(from: observationContextJSON),
            forKey: "observation_context",
            in: &payload
        )

        return try jsonData(from: payload)
    }

    static func multimodalBody(
        r2ObjectKeys: [String],
        audioR2ObjectKeys: [String],
        videoR2ObjectKeys: [String] = [],
        imageBase64s: [String],
        audioBase64s: [String],
        videoFrameCount: Int? = nil,
        visualMediaItems: [IdentifyVisualMediaItem]? = nil,
        audioMediaItems: [IdentifyAudioMediaItem]? = nil,
        observationContextsJSON: [String],
        mimeType: String,
        telemetry: CaptureTelemetry,
        context: InferenceRequestContext,
        clientScanId: String,
        preferredGoal: FieldTripPreferredGoal? = nil
    ) throws -> Data {
        try MerianNetworkClient.validateMultiModalPayloadBudget(
            imageBase64s: imageBase64s,
            audioBase64s: audioBase64s
        )

        var payload = telemetryPayloadFields(
            telemetry: telemetry,
            context: context,
            clientScanId: clientScanId
        )
        if !r2ObjectKeys.isEmpty {
            payload["r2ObjectKeys"] = r2ObjectKeys
        }
        if !audioR2ObjectKeys.isEmpty {
            payload["audioR2ObjectKeys"] = audioR2ObjectKeys
        }
        if !videoR2ObjectKeys.isEmpty {
            payload["videoR2ObjectKeys"] = videoR2ObjectKeys
        }
        if !imageBase64s.isEmpty {
            payload["imageBase64s"] = imageBase64s
        }
        if !audioBase64s.isEmpty {
            payload["audioBase64s"] = audioBase64s
        }
        if let videoFrameCount, videoFrameCount > 0 {
            payload["videoFrameCount"] = videoFrameCount
        }
        if let visualMediaItems, !visualMediaItems.isEmpty {
            payload["visualMediaItems"] = visualMediaItems.map(\.jsonObject)
        }
        if let audioMediaItems, !audioMediaItems.isEmpty {
            payload["audioMediaItems"] = audioMediaItems.map(\.jsonObject)
        }

        let observationContexts = observationContextObjects(from: observationContextsJSON)
        if !observationContexts.isEmpty {
            payload["observation_contexts"] = observationContexts
        }
        payload["mimeType"] = mimeType
        if let preferredGoal {
            payload["preferred_goal"] = [
                "user_field_trip_id": preferredGoal.userFieldTripId,
                "item_id": preferredGoal.itemId
            ]
        }

        return try jsonData(from: payload)
    }

    private static func telemetryPayloadFields(
        telemetry: CaptureTelemetry,
        context: InferenceRequestContext,
        clientScanId: String?
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "user_id": context.userId,
            "deviceLocale": context.deviceLocale,
            "deviceTimeZone": context.deviceTimeZone,
            "currentMonth": context.currentMonth,
            "timeOfDay": context.timeOfDay
        ]

        setIfPresent(context.depthScaleText, forKey: "depthScaleText", in: &payload)
        setIfPresent(telemetry.zoomFactor.map { Double($0) }, forKey: "zoomFactor", in: &payload)
        setIfPresent(telemetry.gpsLatitude, forKey: "gpsLatitude", in: &payload)
        setIfPresent(telemetry.gpsLongitude, forKey: "gpsLongitude", in: &payload)
        setIfPresent(telemetry.gpsElevation, forKey: "gpsElevation", in: &payload)
        let publicLocationLabel = context.defaultGeoprivacy == "private"
            ? nil
            : ExploreLocationPrivacy.displayLabel(from: telemetry.locationName)
        setIfPresent(telemetry.locationName, forKey: "semanticLocation", in: &payload)
        setIfPresent(publicLocationLabel, forKey: "publicLocationLabel", in: &payload)
        setIfPresent(context.defaultGeoprivacy, forKey: "geoprivacy", in: &payload)
        setIfPresent(telemetry.weatherCondition, forKey: "weatherCondition", in: &payload)
        setIfPresent(telemetry.weatherTemperatureF, forKey: "weatherTemperatureF", in: &payload)
        setIfPresent(context.deviceRegion, forKey: "deviceRegion", in: &payload)
        setIfPresent(telemetry.timestamp, forKey: "timestamp", in: &payload)
        setIfPresent(telemetry.estimatedSizeCm, forKey: "estimated_size_cm", in: &payload)
        setIfPresent(clientScanId, forKey: "client_scan_id", in: &payload)

        return payload
    }

    private static func observationContextObject(from json: String?) -> [String: Any]? {
        json.flatMap { rawJSON in
            guard let data = rawJSON.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return object
        }
    }

    static func normalizedGeoprivacy(_ value: String) -> String {
        switch value {
        case "private", "obscured":
            return value
        default:
            return "open"
        }
    }

    private static func observationContextObjects(from jsons: [String]) -> [[String: Any]] {
        jsons.compactMap { json in
            guard let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return object
        }
    }

    private static func setIfPresent<T>(_ value: T?, forKey key: String, in payload: inout [String: Any]) {
        if let value {
            payload[key] = value
        }
    }

    private static func jsonData(from payload: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: payload)
    }
}

// MARK: - TLS Certificate Pinning

/// Validates the server certificate chain for *.supabase.co against pinned SHA-256 hashes.
///
/// The check walks the full certificate chain (leaf → intermediate → root).  A connection
/// is accepted if ANY certificate in the chain matches a pinned hash.  Pinning both the
/// leaf and the intermediate CA means the pin survives leaf rotation (every ~90 days for
/// Let's Encrypt certs) as long as the intermediate CA stays constant.
///
/// Pinning is skipped in DEBUG builds to allow MITM proxies (Charles, Proxyman).
///
/// --- Rotation runbook ---
/// 1. Before the leaf cert expires, run:
///      openssl s_client -connect qlarqavoqhkuwzmevrmf.supabase.co:443 </dev/null \
///        | openssl x509 -outform DER | openssl dgst -sha256 -binary | base64
/// 2. Add the new leaf hash alongside the existing one.
/// 3. Ship the app update.  Old builds keep working via the intermediate CA hash.
/// 4. After the old leaf has expired everywhere, remove the stale leaf hash.
///
/// Intermediate CA hash (changes much less often — update only if Supabase migrates CAs):
///   openssl s_client -connect qlarqavoqhkuwzmevrmf.supabase.co:443 -showcerts </dev/null \
///     | awk 'n==1{cert=cert"\n"$0} /BEGIN CERT/{n++} /END CERT/{if(n==2)exit}' \
///     | openssl x509 -outform DER | openssl dgst -sha256 -binary | base64
private final class MerianRequestUploadDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let expectedBodyBytes: Int64
    private let onBodySent: @Sendable () -> Void
    private let lock = NSLock()
    private var didNotify = false

    init(expectedBodyBytes: Int, onBodySent: @escaping @Sendable () -> Void) {
        self.expectedBodyBytes = Int64(expectedBodyBytes)
        self.onBodySent = onBodySent
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesSent >= expectedBodyBytes else { return }
        notifyBodySentIfNeeded()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        guard let transaction = metrics.transactionMetrics.last else { return }
        let requestUpload = transaction.requestStartDate.flatMap { start in
            transaction.requestEndDate.map { $0.timeIntervalSince(start) }
        }
        let timeToFirstByte = transaction.requestEndDate.flatMap { requestEnd in
            transaction.responseStartDate.map { $0.timeIntervalSince(requestEnd) }
        }
        let responseTransfer = transaction.responseStartDate.flatMap { responseStart in
            transaction.responseEndDate.map { $0.timeIntervalSince(responseStart) }
        }
        MerianLog.network.debug(
            "[⏱ BENCH] URLSession request_upload=\(String(format: "%.3f", requestUpload ?? 0), privacy: .public)s ttfb_after_upload=\(String(format: "%.3f", timeToFirstByte ?? 0), privacy: .public)s response_transfer=\(String(format: "%.3f", responseTransfer ?? 0), privacy: .public)s"
        )
    }

    func notifyBodySentIfNeeded() {
        lock.lock()
        let shouldNotify = !didNotify
        didNotify = true
        lock.unlock()
        if shouldNotify { onBodySent() }
    }
}

private final class MerianTLSDelegate: NSObject, URLSessionDelegate {
    // Leaf cert (expires ~90 days — rotate per runbook above).
    // Intermediate CA (Sectigo RSA Domain Validation Secure Server CA) — stable across leaf rotations.
    static let pinnedCertHashes: Set<String> = [
        "OYvM4tmVyyPLCSqTe1tYvZW0CKRfv4mre7EUA0eJrn0=", // leaf — qlarqavoqhkuwzmevrmf.supabase.co
        "HfwWBfutNY2LyET3bRUgP6ycpcGnn9SFf/ryhk++v5Y="  // intermediate CA (backup across leaf rotations)
    ]

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        #if DEBUG
        // Skip pinning in debug builds to allow MITM proxies (Charles, Proxyman).
        completionHandler(.performDefaultHandling, nil)
        #else
        // Only pin the Supabase domain; let R2 and other hosts use default ATS validation.
        guard challenge.protectionSpace.host.hasSuffix("supabase.co"),
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              !MerianTLSDelegate.pinnedCertHashes.isEmpty,
              let serverTrust = challenge.protectionSpace.serverTrust,
              let certChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Walk the full chain so the intermediate CA hash works as a genuine fallback.
        let matched = certChain.contains { cert in
            let certData = SecCertificateCopyData(cert) as Data
            let hash = Data(SHA256.hash(data: certData)).base64EncodedString()
            return MerianTLSDelegate.pinnedCertHashes.contains(hash)
        }

        if matched {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            MerianLog.network.error("TLS cert pinning failed for \(challenge.protectionSpace.host, privacy: .public)")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
        #endif
    }
}

// MARK: - Merian Network Client

/// Authenticated HTTP client for all Supabase Edge Function and R2 storage calls.
final class MerianNetworkClient {

    // MARK: - Singleton Architecture
    static let shared = MerianNetworkClient()

    private let supabaseUrl = MerianEnvironment.supabaseUrl
    private let supabaseAnonKey = MerianEnvironment.supabaseAnonKey
    private let speciesDictionaryCacheTTL: TimeInterval = 10 * 60
    private let speciesDictionaryCacheLimit = 64
    private let speciesDictionaryCacheLock = NSLock()
    private var speciesDictionaryCache: [String: SpeciesDictionaryCacheEntry] = [:]
    private let speciesObservationStatsCacheTTL: TimeInterval = 5 * 60
    private let speciesObservationStatsCacheLimit = 64
    private let speciesObservationStatsCacheLock = NSLock()
    private var speciesObservationStatsCache: [String: SpeciesObservationStatsCacheEntry] = [:]
    private static let functionRouteRetryDelays: [UInt64] = [
        1_000_000_000,
        2_000_000_000,
        4_000_000_000
    ]
    private static let safelyReplayableReadFunctionNames: Set<String> = [
        "check-public-username",
        "check-scan-status",
        "get-community-identification-detail",
        "get-community-identification-feed",
        "get-explore-author-posts",
        "get-explore-author-profile",
        "get-explore-comment-replies",
        "get-explore-comments",
        "get-explore-composer-media",
        "get-explore-feed",
        "get-explore-hashtag-posts",
        "get-explore-map-points",
        "get-explore-media-incidents",
        "get-explore-mention-suggestions",
        "get-explore-notifications",
        "get-explore-post",
        "get-explore-post-detail",
        "get-explore-species-posts",
        "get-explore-unread-notification-count",
        "get-filtered-discovery-feed",
        "get-scan-explore-share-state",
        "search-community-taxa",
        "species-dictionary",
        "species-observation-stats"
    ]
    private static let idempotencyAwareFunctionNames: Set<String> = [
        "enrich-scan",
        "explore-post-chat",
        "identify",
        "identify-multimodal",
        "insight-chat",
        "request-community-identification",
        "share-scan-to-explore",
        "update-explore-field-notes"
    ]
    private static let insightChatPromptCategoryAllowlist: Set<String> = [
        "confidence",
        "ecology",
        "evidence",
        "field_notes",
        "generic",
        "habitat",
        "hazard",
        "invasive",
        "lookalike_compare",
        "season"
    ]
    private static let unsafeInsightChatPromptPatterns = [
        #"\b(?:can|could|should|may|would)\s+(?:i|we|you)\s+(?:safely\s+)?(?:eat|consume|taste|cook|bake|brew|forage|feed|kill|exterminate|trap|capture|handle|pick\s+up|relocate|collect|harvest|remove\s+(?:it|this|that|a\s+nest)|take\s+(?:it|this|that)\s+home)\b"#,
        #"\bhow\s+(?:(?:do|can|could|should|would|may)\s+(?:i|we|you)\s+|to\s+)(?:eat|consume|taste|cook|bake|brew|forage|feed|kill|exterminate|trap|capture|handle|pick\s+up|relocate|collect|harvest|remove\s+(?:it|this|that|a\s+nest)|take\s+(?:it|this|that)\s+home)\b"#,
        #"\b(?:edible|safe\s+to\s+(?:eat|consume|taste|cook|brew|feed|handle|pick\s+up|capture|relocate)|(?:can|could|should|may|would)\s+(?:this|that|it|these|those)\s+be\s+(?:eaten|consumed|tasted|cooked|brewed|fed|killed|trapped|captured|handled|relocated|collected|harvested|removed|taken\s+home))\b"#,
        #"\b(?:(?:can|could|should|may|would)\s+(?:my|our)\s+(?:dog|cat|pet|livestock)\s+(?:eat|consume|taste)|(?:what\s+happens\s+if|after)\s+(?:i|we|you|someone|a\s+person|a\s+child|my\s+(?:dog|cat|pet))\s+(?:eat|ate|consume|consumed|taste|tasted|ingest|ingested))\b"#,
        #"\b(?:(?:best|safest|proper|recommended)\s+(?:ways?|methods?)\s+to|(?:instructions?|steps?|tips?|advice|guide)\s+(?:for|on|to)|(?:tell|show)\s+me\s+how\s+to)\s+(?:eat(?:ing)?|consum(?:e|ing)|tast(?:e|ing)|cook(?:ing)?|bak(?:e|ing)|brew(?:ing)?|forag(?:e|ing)|feed(?:ing)?|treat(?:ing)?|medicat(?:e|ing)|kill(?:ing)?|exterminat(?:e|ing)|trap(?:ping)?|captur(?:e|ing)|handl(?:e|ing)|pick(?:ing)?\s+up|relocat(?:e|ing)|collect(?:ing)?|harvest(?:ing)?|remov(?:e|ing)\s+(?:it|this|that|a\s+nest)|tak(?:e|ing)\s+(?:it|this|that)\s+home)\b"#,
        #"\b(?:(?:can|could|should|may|would)\s+(?:i|we|you)\s+(?:treat|medicate|manage)\b.{0,40}\b(?:rash|bite|sting|venom|allergic\s+reaction|poisoning|exposure)|what\s+should\s+(?:i|we|you|someone|a\s+person|a\s+child)\s+do\b.{0,30}\b(?:if|after)\b.{0,30}\b(?:bitten|stung|ate|ingested|rash|allergic\s+reaction|poisoning|exposure))\b"#,
        #"\b(?:dosage|antidote|treatment\s+(?:advice|instructions?|plan)|medical\s+treatment|veterinary\s+treatment|medicine\s+for|pesticide\s+(?:instructions?|application|use)|apply\s+(?:a\s+)?pesticide|(?:use|apply)\s+poison|poison\s+(?:it|this|that|them)|extermination\s+instructions?)\b"#,
        #"\b(?:legal|allowed|permit(?:ted)?|permission)\b.{0,30}\b(?:collect|harvest|capture|take|remove|relocate)\b"#,
        #"\b(?:gps|coordinates?|latitude|longitude|exact\s+location|where\s+exactly)\b"#,
        #"\b(?:identify|recognize|name|who\s+is)\b.{0,30}\b(?:person|human|face)\b"#
    ]
    private static let internalUUIDPattern =
        #"\b[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\b"#
    private static let maxFieldChatResponseBytes = 1_048_576
    private static let maxFieldChatMessageCharacters = 4_000

    private struct SpeciesDictionaryCacheEntry {
        let value: SpeciesDictionaryEntry
        let storedAt: Date
    }

    private struct SpeciesObservationStatsCacheEntry {
        let value: SpeciesObservationStatsEntry
        let storedAt: Date
    }

    // MARK: - URLSession

    #if DEBUG
    /// Allows test suites to inject ephemeral configurations (like MockURLProtocol).
    var overridingSession: URLSession? {
        didSet { resetSpeciesDictionaryCacheForTesting() }
    }
    #endif

    private var activeSession: URLSession {
        #if DEBUG
        if let overridingSession { return overridingSession }
        #endif
        return session
    }

    /// Dedicated session with sensible timeouts, connection limits, and TLS pinning.
    /// Replaces `URLSession.shared` to avoid inheriting the system-wide shared configuration.
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30       // TCP + TLS + first-byte wait
        config.timeoutIntervalForResource = 90      // Hard cap; Gemini can be slow on bad connections
        config.httpMaximumConnectionsPerHost = 6
        config.httpShouldSetCookies = false         // Auth uses headers, not cookies
        config.urlCache = nil                       // Keep URLCache off; public dictionary pages use scoped memoization.
        return URLSession(configuration: config, delegate: MerianTLSDelegate(), delegateQueue: nil)
    }()

    // MARK: - URL Construction

    /// Builds a URL for the given Edge Function path segment.
    /// Throws `MerianError.invalidURL` rather than crashing if `supabaseUrl` is misconfigured.
    private func endpointURL(_ function: String) throws -> URL {
        guard MerianEnvironment.isSupabaseConfigured else {
            MerianLog.network.error("Network request blocked because Supabase environment configuration is incomplete.")
            throw MerianError.invalidURL
        }
        guard let url = URL(string: "\(supabaseUrl)/functions/v1/\(function)") else {
            throw MerianError.invalidURL
        }
        return url
    }

    /// Opens the actual pinned inference connection pool used by live scans.
    /// Authentication is prewarmed separately because Supabase Auth owns a
    /// different URLSession.
    func prewarmInferenceEndpoint() async {
        do {
            let url = try endpointURL("identify-multimodal")
            var request = URLRequest(
                url: url,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 5
            )
            request.httpMethod = "OPTIONS"
            _ = try await activeSession.data(for: request)
        } catch {
            MerianLog.network.debug(
                "Inference endpoint prewarm skipped: \(error.localizedDescription, privacy: .private)"
            )
        }
    }

    private func makeExploreDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private func makeInsightChatDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date =
                DateUtilities.iso8601FractionalFormatter.date(from: value) ??
                DateUtilities.iso8601Formatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO 8601 date: \(value)"
            )
        }
        return decoder
    }

    /// Treats a chat HTTP 200 as candidate evidence until every message is
    /// bound to the requested scan/post and to the envelope's conversation.
    private func decodeInsightChatResponse(
        _ data: Data,
        expectedSubjectId: String,
        expectedClientMessageId: String? = nil,
        expectedUserMessageText: String? = nil
    ) throws -> InsightChatResponse {
        try validateFieldChatResponseSize(data)
        let response: InsightChatResponse
        do {
            response = try makeInsightChatDecoder()
                .decode(InsightChatEnvelope.self, from: data)
                .data
        } catch {
            throw MerianError.invalidResponse
        }

        let expectedSubjectId = expectedSubjectId
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let conversationId = response.conversationId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let messageIds = response.messages.compactMap {
            UUID(uuidString: $0.id)
        }
        let expectedClientMessageId = expectedClientMessageId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedUserMessageText = expectedUserMessageText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let requestMessages = expectedClientMessageId.map { requestId in
            response.messages.filter { message in
                message.clientMessageId?.caseInsensitiveCompare(requestId) ==
                    .orderedSame
            }
        } ?? []
        let requestIsValid: Bool
        switch (expectedClientMessageId, expectedUserMessageText) {
        case (nil, nil):
            requestIsValid = true
        case let (requestId?, userMessageText?):
            requestIsValid =
                UUID(uuidString: requestId) != nil &&
                !userMessageText.isEmpty &&
                userMessageText.count <= 600 &&
                requestMessages.count == 2 &&
                requestMessages.filter {
                    $0.role == .user
                }.count == 1 &&
                requestMessages.filter {
                    $0.role == .assistant
                }.count == 1 &&
                requestMessages.first {
                    $0.role == .user
                }?.text == userMessageText
        default:
            requestIsValid = false
        }
        guard !expectedSubjectId.isEmpty,
              response.subjectId?.caseInsensitiveCompare(
                  expectedSubjectId
              ) == .orderedSame,
              response.limits.maxUserMessageCharacters == 600,
              response.limits.maxMessagesPerConversation == 30,
              response.limits.dailySendLimit == 20,
              response.limits.sendsRemainingToday >= 0,
              response.limits.sendsRemainingToday <=
                response.limits.dailySendLimit,
              response.messages.count <=
                response.limits.maxMessagesPerConversation,
              response.conversationId == nil ||
                (
                    response.conversationId == conversationId &&
                    conversationId?.isEmpty == false &&
                    conversationId.flatMap {
                        UUID(uuidString: $0)
                    } != nil
                ),
              response.messages.isEmpty || conversationId != nil,
              messageIds.count == response.messages.count,
              Set(messageIds).count == messageIds.count,
              response.messages.allSatisfy({ message in
                  let text = message.text
                      .trimmingCharacters(in: .whitespacesAndNewlines)
                  return message.scanId.caseInsensitiveCompare(
                      expectedSubjectId
                  ) == .orderedSame &&
                    message.conversationId.caseInsensitiveCompare(
                        conversationId ?? ""
                    ) == .orderedSame &&
                    text == message.text &&
                    !text.isEmpty &&
                    text.count <= Self.maxFieldChatMessageCharacters &&
                    (
                        message.clientMessageId == nil ||
                        message.clientMessageId.flatMap {
                            UUID(uuidString: $0)
                        } != nil
                    )
              }),
              requestIsValid else {
            throw MerianError.invalidResponse
        }
        return response
    }

    private func validateFieldChatResponseSize(_ data: Data) throws {
        guard data.count <= Self.maxFieldChatResponseBytes else {
            throw MerianError.invalidResponse
        }
    }

    private func decodeInsightChatFeedbackResponse(
        _ data: Data,
        expectedSubjectId: String,
        expectedMessageId: String,
        expectedRating: InsightChatFeedbackRating
    ) throws -> InsightChatFeedbackResponse {
        try validateFieldChatResponseSize(data)
        let response: InsightChatFeedbackResponse
        do {
            response = try JSONDecoder()
                .decode(InsightChatFeedbackEnvelope.self, from: data)
                .data
        } catch {
            throw MerianError.invalidResponse
        }
        guard response.ok,
              response.subjectId?.caseInsensitiveCompare(
                  expectedSubjectId
              ) == .orderedSame,
              UUID(uuidString: expectedMessageId) != nil,
              UUID(uuidString: response.messageId) != nil,
              response.messageId.caseInsensitiveCompare(expectedMessageId) ==
                .orderedSame,
              response.rating == expectedRating else {
            throw MerianError.invalidResponse
        }
        return response
    }

    private func decodeInsightChatFeatureFeedbackResponse(
        _ data: Data,
        expectedSubjectId: String,
        expectedSentiment: InsightChatFeatureFeedbackSentiment?
    ) throws -> InsightChatFeatureFeedbackResponse {
        try validateFieldChatResponseSize(data)
        let response: InsightChatFeatureFeedbackResponse
        do {
            response = try JSONDecoder()
                .decode(InsightChatFeatureFeedbackEnvelope.self, from: data)
                .data
        } catch {
            throw MerianError.invalidResponse
        }
        guard response.ok,
              response.subjectId?.caseInsensitiveCompare(
                  expectedSubjectId
              ) == .orderedSame,
              UUID(uuidString: response.id) != nil,
              response.sentiment == expectedSentiment else {
            throw MerianError.invalidResponse
        }
        return response
    }

    private func decodeInsightChatSummaryResponse(
        _ data: Data,
        expectedSubjectId: String
    ) throws -> InsightChatSummaryResponse {
        try validateFieldChatResponseSize(data)
        let response: InsightChatSummaryResponse
        do {
            response = try JSONDecoder()
                .decode(InsightChatSummaryEnvelope.self, from: data)
                .data
        } catch {
            throw MerianError.invalidResponse
        }
        let summaryText = response.summaryText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard response.subjectId?.caseInsensitiveCompare(
                  expectedSubjectId
              ) == .orderedSame,
              !summaryText.isEmpty,
              summaryText.count <= 4_000,
              summaryText.range(
                  of: Self.internalUUIDPattern,
                  options: [.regularExpression, .caseInsensitive]
              ) == nil else {
            throw MerianError.invalidResponse
        }
        return InsightChatSummaryResponse(
            subjectId: response.subjectId,
            summaryText: summaryText
        )
    }

    private func decodeInsightChatPromptSuggestionsResponse(
        _ data: Data,
        expectedSubjectId: String
    ) throws -> InsightChatPromptSuggestionsResponse {
        try validateFieldChatResponseSize(data)
        let response: InsightChatPromptSuggestionsResponse
        do {
            response = try JSONDecoder()
                .decode(InsightChatPromptSuggestionsEnvelope.self, from: data)
                .data
        } catch {
            throw MerianError.invalidResponse
        }
        let conversationId = response.conversationId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var normalizedPrompts = Set<String>()
        guard response.subjectId?.caseInsensitiveCompare(
                  expectedSubjectId
              ) == .orderedSame,
              response.conversationId == nil ||
                (
                    conversationId?.isEmpty == false &&
                    conversationId.flatMap {
                        UUID(uuidString: $0)
                    } != nil
                ),
              response.prompts.count <= 3,
              response.prompts.allSatisfy({ prompt in
                  let text = prompt.text
                      .trimmingCharacters(in: .whitespacesAndNewlines)
                  let category = prompt.category
                      .trimmingCharacters(in: .whitespacesAndNewlines)
                  return text == prompt.text &&
                    !text.isEmpty &&
                    text.count <= 120 &&
                    category == prompt.category &&
                    Self.insightChatPromptCategoryAllowlist.contains(
                        category
                    ) &&
                    Self.unsafeInsightChatPromptPatterns.allSatisfy {
                        text.range(
                            of: $0,
                            options: [
                                .regularExpression,
                                .caseInsensitive
                            ]
                        ) == nil
                    } &&
                    normalizedPrompts.insert(text.lowercased()).inserted
              }) else {
            throw MerianError.invalidResponse
        }
        return response
    }

    private static func isMissingAuthSessionError(responseData: Data, fallbackMessage: String) -> Bool {
        if let payload = try? JSONDecoder().decode(EdgeErrorPayload.self, from: responseData) {
            if payload.code == "auth_session_missing" {
                return true
            }

            if payload.error?.localizedCaseInsensitiveContains("Auth session missing") == true {
                return true
            }
        }

        return fallbackMessage.localizedCaseInsensitiveContains("Auth session missing")
    }

    static func isPlatformFunctionRouteUnavailable(
        evidence: EdgeFunctionRouteResponseEvidence,
        responseData: Data
    ) -> Bool {
        let handlerMarker = evidence.handlerMarker?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard evidence.statusCode == 404,
              handlerMarker != "1" else {
            return false
        }

        if evidence.supabaseErrorCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("NOT_FOUND") == .orderedSame {
            return true
        }

        if let payload = try? JSONDecoder().decode(EdgeErrorPayload.self, from: responseData) {
            if payload.code?.caseInsensitiveCompare("NOT_FOUND") == .orderedSame {
                return true
            }

            if payload.message?.localizedCaseInsensitiveContains("Requested function was not found") == true
                || payload.error?.localizedCaseInsensitiveContains("Requested function was not found") == true {
                return true
            }
        }

        if String(data: responseData, encoding: .utf8)?
            .localizedCaseInsensitiveContains("Requested function was not found") == true {
            return true
        }

        return evidence.hasGatewayVersion && !evidence.hasExecutionId
    }

    static func stableEdgeErrorCode(responseData: Data) -> String? {
        guard let payload = try? JSONDecoder().decode(
            EdgeErrorPayload.self,
            from: responseData
        ),
              let rawCode = payload.code?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
              rawCode.range(
                of: #"^[a-z][a-z0-9_]{1,63}$"#,
                options: .regularExpression
              ) != nil else {
            return nil
        }
        return rawCode
    }

    static func stableEdgeErrorCode(from error: Error) -> String? {
        guard case let MerianError.httpError(_, message) = error else {
            return nil
        }
        return stableEdgeErrorCode(responseData: Data(message.utf8))
    }

    static func isRecoverableInferenceConflict(_ error: Error) -> Bool {
        guard case let MerianError.httpError(statusCode, _) = error,
              statusCode == 409,
              let code = stableEdgeErrorCode(from: error) else {
            return false
        }
        return code == "ai_request_already_completed"
            || code == "ai_request_in_progress"
            || code == "scan_already_complete"
            || code == "scan_already_finalized"
    }

    private static func canReplayAfterAmbiguousFailure(
        url: URL,
        method: String,
        idempotencyKey: String?
    ) -> Bool {
        if method.caseInsensitiveCompare("GET") == .orderedSame {
            return true
        }
        if idempotencyKey != nil,
           idempotencyAwareFunctionNames.contains(url.lastPathComponent) {
            return true
        }
        return safelyReplayableReadFunctionNames.contains(url.lastPathComponent)
    }

    #if DEBUG
    static func isPlatformFunctionRouteUnavailableForTesting(
        response: HTTPURLResponse,
        responseData: Data
    ) -> Bool {
        isPlatformFunctionRouteUnavailable(
            evidence: EdgeFunctionRouteResponseEvidence(response: response),
            responseData: responseData
        )
    }

    static func canReplayAfterAmbiguousFailureForTesting(
        url: URL,
        method: String,
        idempotencyKey: String? = nil
    ) -> Bool {
        canReplayAfterAmbiguousFailure(
            url: url,
            method: method,
            idempotencyKey: idempotencyKey
        )
    }
    #endif

    static func shouldRegenerateSessionAfterMissingAuthSession(
        hasAuthenticatedOAuth: Bool,
        isGuestUser: Bool
    ) -> Bool {
        !hasAuthenticatedOAuth && isGuestUser
    }

    #if DEBUG
    func resetSpeciesDictionaryCacheForTesting() {
        speciesDictionaryCacheLock.lock()
        speciesDictionaryCache.removeAll()
        speciesDictionaryCacheLock.unlock()

        speciesObservationStatsCacheLock.lock()
        speciesObservationStatsCache.removeAll()
        speciesObservationStatsCacheLock.unlock()
    }
    #endif

    private func makeInferenceRequestContext(telemetry: CaptureTelemetry) async -> InferenceRequestContext {
        let authUserId = try? await SupabaseManager.shared.client.auth.session.user.id.uuidString
        let (deviceId, defaultGeoprivacy) = await MainActor.run {
            (
                DeviceIdentityManager.shared.deviceId,
                AppDIContainer.shared.profileViewModel.defaultGeoprivacy
            )
        }
        return InferencePayloadBuilder.makeContext(
            userId: authUserId ?? deviceId,
            telemetry: telemetry,
            defaultGeoprivacy: defaultGeoprivacy
        )
    }

    private func makeAuthenticatedJSONRequest(
        url: URL,
        bodyData: Data,
        timeoutInterval: TimeInterval = 90.0,
        idempotencyKey: String? = nil
    ) async throws -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        request.httpBody = bodyData

        let authHeaders = try await SupabaseManager.shared.getValidAuthHeaders()
        for (key, val) in authHeaders {
            request.setValue(val, forHTTPHeaderField: key)
        }

        return request
    }

    // MARK: - Authenticated Request Core

    private func performAuthenticatedRequest(
        url: URL,
        method: String,
        body: Data? = nil,
        timeoutInterval: TimeInterval = 30.0,
        isRetry: Bool = false,
        functionRouteRetryAttempt: Int = 0,
        idempotencyKey: String? = nil,
        onRequestBodySent: (@Sendable () -> Void)? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()

        let requestStart = CFAbsoluteTimeGetCurrent()
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeoutInterval)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        if let body = body {
            request.httpBody = body
        }

        // In DEBUG, skip the live auth round-trip when a mock session is injected.
        // The Supabase SDK uses its own internal URLSession for token refresh which
        // MockURLProtocol cannot intercept, causing the test to hit the real network.
        #if DEBUG
        if overridingSession == nil {
            let authHeaders = try await SupabaseManager.shared.getValidAuthHeaders()
            for (key, val) in authHeaders {
                request.setValue(val, forHTTPHeaderField: key)
            }
        }
        #else
        let authHeaders = try await SupabaseManager.shared.getValidAuthHeaders()
        for (key, val) in authHeaders {
            request.setValue(val, forHTTPHeaderField: key)
        }
        #endif
        try Task.checkCancellation()

        let constrainedNetwork = await MainActor.run {
            OfflineQueueManager.shared.isCurrentNetworkConstrained
        }
        try Task.checkCancellation()

        request.setValue(constrainedNetwork ? "true" : "false", forHTTPHeaderField: "X-Merian-Constrained-Network")
        let authCompletedAt = CFAbsoluteTimeGetCurrent()

        let (data, response): (Data, URLResponse)
        var requestUploadDelegate: MerianRequestUploadDelegate?
        do {
            if let body, let onRequestBodySent {
                let uploadDelegate = MerianRequestUploadDelegate(
                    expectedBodyBytes: body.count,
                    onBodySent: onRequestBodySent
                )
                requestUploadDelegate = uploadDelegate
                (data, response) = try await activeSession.data(for: request, delegate: uploadDelegate)
            } else {
                (data, response) = try await activeSession.data(for: request)
            }
        } catch let urlError as URLError {
            // A transport failure means the inline request can no longer be the
            // sole owner of the uplink. Release the durable queue immediately;
            // the callback is idempotent and remains safe if upload progress
            // already reported completion.
            onRequestBodySent?()
            // Foundation commonly represents cancellation of URLSession's async
            // bridge as NSURLErrorCancelled. Normalize it only when this Swift
            // task owns the cancellation; independently canceled sessions retain
            // their original transport error.
            try Task.checkCancellation()

            let transientCodes: Set<URLError.Code> = [
                .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet
            ]
            if transientCodes.contains(urlError.code),
               !isRetry,
               Self.canReplayAfterAmbiguousFailure(
                   url: url,
                   method: method,
                   idempotencyKey: idempotencyKey
                ) {
                MerianLog.network.debug("Transient network error \(urlError.code.rawValue, privacy: .public) — retrying in 2s.")
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return try await performAuthenticatedRequest(
                    url: url,
                    method: method,
                    body: body,
                    timeoutInterval: timeoutInterval,
                    isRetry: true,
                    functionRouteRetryAttempt: functionRouteRetryAttempt,
                    idempotencyKey: idempotencyKey,
                    onRequestBodySent: onRequestBodySent
                )
            }
            throw urlError
        }
        // Some custom URLProtocol implementations do not emit upload progress.
        // A received response proves the request body finished sending.
        requestUploadDelegate?.notifyBodySentIfNeeded()
        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MerianError.invalidResponse
        }

        if !(200..<300).contains(httpResponse.statusCode) {
            let errString = String(data: data, encoding: .utf8) ?? "Unknown"
            MerianLog.network.debug("Edge function failed [\(httpResponse.statusCode, privacy: .public)]: \(errString, privacy: .public)")

            let platformFunctionRouteUnavailable = Self.isPlatformFunctionRouteUnavailable(
                evidence: EdgeFunctionRouteResponseEvidence(response: httpResponse),
                responseData: data
            )
            if platformFunctionRouteUnavailable {
                if functionRouteRetryAttempt < Self.functionRouteRetryDelays.count {
                    let delay = Self.functionRouteRetryDelays[functionRouteRetryAttempt]
                    let delaySeconds = delay / 1_000_000_000
                    MerianLog.network.debug(
                        "Supabase route metadata unavailable for \(url.lastPathComponent, privacy: .public) — retrying in \(delaySeconds, privacy: .public)s (attempt \(functionRouteRetryAttempt + 1, privacy: .public)/\(Self.functionRouteRetryDelays.count, privacy: .public))."
                    )
                    try await Task.sleep(nanoseconds: delay)
                    return try await performAuthenticatedRequest(
                        url: url,
                        method: method,
                        body: body,
                        timeoutInterval: timeoutInterval,
                        isRetry: isRetry,
                        functionRouteRetryAttempt: functionRouteRetryAttempt + 1,
                        idempotencyKey: idempotencyKey,
                        onRequestBodySent: onRequestBodySent
                    )
                }

                throw MerianError.edgeFunctionUnavailable
            }

            if httpResponse.statusCode == 401 && !isRetry {
                if Self.isMissingAuthSessionError(responseData: data, fallbackMessage: errString) {
                    if await SupabaseManager.shared.refreshActiveSessionForRetry() {
                        return try await performAuthenticatedRequest(
                            url: url,
                            method: method,
                            body: body,
                            timeoutInterval: timeoutInterval,
                            isRetry: true,
                            functionRouteRetryAttempt: functionRouteRetryAttempt,
                            idempotencyKey: idempotencyKey,
                            onRequestBodySent: onRequestBodySent
                        )
                    }

                    let hasAuthenticatedOAuth = KeychainManager.shared.bool(forKey: KeychainKeys.hasAuthenticatedOAuth)
                    let isGuest = await SupabaseManager.shared.isGuestUser
                    if Self.shouldRegenerateSessionAfterMissingAuthSession(
                        hasAuthenticatedOAuth: hasAuthenticatedOAuth,
                        isGuestUser: isGuest
                    ) {
                        MerianLog.network.debug("Missing anonymous auth session detected — regenerating ghost session.")
                        if await SupabaseManager.shared.resetGhostSessionForRetry() {
                            try await Task.sleep(nanoseconds: 1_500_000_000)
                            return try await performAuthenticatedRequest(
                                url: url,
                                method: method,
                                body: body,
                                timeoutInterval: timeoutInterval,
                                isRetry: true,
                                functionRouteRetryAttempt: functionRouteRetryAttempt,
                                idempotencyKey: idempotencyKey,
                                onRequestBodySent: onRequestBodySent
                            )
                        }

                        await SupabaseManager.shared.clearLocalSessionAfterAuthFailure()
                    } else {
                        MerianLog.network.debug("Missing auth session detected for authenticated user; preserving local session.")
                    }

                    throw MerianError.invalidResponse
                }

                let hasAuthenticatedOAuth = KeychainManager.shared.bool(forKey: KeychainKeys.hasAuthenticatedOAuth)
                if hasAuthenticatedOAuth {
                    // OAuth user whose token expired — surface the 401 so the UI can prompt re-auth.
                    throw MerianError.invalidResponse
                }

                let isGuest = await SupabaseManager.shared.isGuestUser
                if isGuest {
                    MerianLog.network.debug("Zombie session detected — regenerating ghost session.")
                    await SupabaseManager.shared.transitionToGhostSession()

                    // Allow ~1.5s for the API gateway to recognize the new token signature.
                    try await Task.sleep(nanoseconds: 1_500_000_000)

                    return try await performAuthenticatedRequest(
                        url: url,
                        method: method,
                        body: body,
                        timeoutInterval: timeoutInterval,
                        isRetry: true,
                        functionRouteRetryAttempt: functionRouteRetryAttempt,
                        idempotencyKey: idempotencyKey,
                        onRequestBodySent: onRequestBodySent
                    )
                } else {
                    throw MerianError.invalidResponse
                }
            }

            // A transport failure or 5xx can occur after a mutation committed.
            // Replay only reads and calls carrying a server-supported idempotency key.
            if httpResponse.statusCode >= 500,
               !isRetry,
               Self.canReplayAfterAmbiguousFailure(
                   url: url,
                   method: method,
                   idempotencyKey: idempotencyKey
               ) {
                MerianLog.network.debug("Server error \(httpResponse.statusCode, privacy: .public) — retrying in 2s.")
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return try await performAuthenticatedRequest(
                    url: url,
                    method: method,
                    body: body,
                    timeoutInterval: timeoutInterval,
                    isRetry: true,
                    functionRouteRetryAttempt: functionRouteRetryAttempt,
                    idempotencyKey: idempotencyKey,
                    onRequestBodySent: onRequestBodySent
                )
            }

            throw MerianError.httpError(statusCode: httpResponse.statusCode, message: errString)
        }

        let responseCompletedAt = CFAbsoluteTimeGetCurrent()
        MerianLog.network.debug(
            "[⏱ BENCH] HTTP \(url.lastPathComponent, privacy: .public) auth=\(String(format: "%.3f", authCompletedAt - requestStart), privacy: .public)s transfer+server=\(String(format: "%.3f", responseCompletedAt - authCompletedAt), privacy: .public)s status=\(httpResponse.statusCode, privacy: .public) requestBytes=\(body?.count ?? 0, privacy: .public) responseBytes=\(data.count, privacy: .public)"
        )
        if let serverTiming = httpResponse.value(forHTTPHeaderField: "Server-Timing") {
            MerianLog.network.debug(
                "[⏱ BENCH] Server-Timing \(serverTiming, privacy: .public) region=\(httpResponse.value(forHTTPHeaderField: "X-Merian-Edge-Region") ?? "unknown", privacy: .public)"
            )
        }
        return (data, httpResponse)
    }

    private func performPublicGETRequest(
        url: URL,
        timeoutInterval: TimeInterval = 20.0,
        isRetry: Bool = false
    ) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()

        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: timeoutInterval)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await activeSession.data(for: request)
        } catch let urlError as URLError {
            try Task.checkCancellation()

            let transientCodes: Set<URLError.Code> = [
                .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet
            ]
            if transientCodes.contains(urlError.code) && !isRetry {
                MerianLog.network.debug("Transient public network error \(urlError.code.rawValue, privacy: .public) — retrying in 2s.")
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return try await performPublicGETRequest(url: url, timeoutInterval: timeoutInterval, isRetry: true)
            }
            throw urlError
        }
        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MerianError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errString = String(data: data, encoding: .utf8) ?? "Unknown"
            MerianLog.network.debug("Public edge function failed [\(httpResponse.statusCode, privacy: .public)]: \(errString, privacy: .public)")

            if httpResponse.statusCode >= 500 && !isRetry {
                MerianLog.network.debug("Public server error \(httpResponse.statusCode, privacy: .public) — retrying in 2s.")
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return try await performPublicGETRequest(url: url, timeoutInterval: timeoutInterval, isRetry: true)
            }

            throw MerianError.httpError(statusCode: httpResponse.statusCode, message: errString)
        }

        return (data, httpResponse)
    }

    // MARK: - Inference

    /// Builds a fully-authenticated POST URLRequest for the /identify edge function.
    ///
    /// Returns the request without executing it so the caller can dispatch it as a
    /// background URLSession download task — enabling result delivery while backgrounded.
    func buildIdentifyRequest(
        r2ObjectKeys: [String],
        telemetry: CaptureTelemetry,
        clientScanId: String,
        description: String? = nil,
        observationContextJSON: String? = nil
    ) async throws -> URLRequest {
        let functionUrl = try endpointURL("identify")
        let context = await makeInferenceRequestContext(telemetry: telemetry)
        let capturedR2ObjectKeys = r2ObjectKeys
        let capturedScanId = clientScanId
        let capturedTelemetry = telemetry
        let capturedDescription = description
        let capturedObservationContextJSON = observationContextJSON
        let bodyData = try await Task.detached(priority: .userInitiated) {
            try InferencePayloadBuilder.identifyBody(
                r2ObjectKeys: capturedR2ObjectKeys,
                imageBase64s: nil,
                mimeType: "image/webp",
                telemetry: capturedTelemetry,
                context: context,
                clientScanId: capturedScanId,
                description: capturedDescription,
                observationContextJSON: capturedObservationContextJSON
            )
        }.value

        return try await makeAuthenticatedJSONRequest(
            url: functionUrl,
            bodyData: bodyData,
            idempotencyKey: capturedScanId
        )
    }

    func analyzeSubject(r2ObjectKeys: [String]?, base64ImageDatas: [String]?, mimeType: String = "image/webp", telemetry: CaptureTelemetry, clientScanId: String? = nil, description: String? = nil, observationContextJSON: String? = nil) async throws -> Data {
        let functionUrl = try endpointURL("identify")
        let context = await makeInferenceRequestContext(telemetry: telemetry)
        let capturedR2ObjectKeys = r2ObjectKeys
        let capturedImageBase64s = base64ImageDatas
        let capturedMimeType = mimeType
        let capturedTelemetry = telemetry
        let capturedClientScanId = clientScanId ?? UUID().uuidString.lowercased()
        let capturedDescription = description
        let capturedObservationContextJSON = observationContextJSON
        let bodyData = try await Task.detached(priority: .userInitiated) {
            try InferencePayloadBuilder.identifyBody(
                r2ObjectKeys: capturedR2ObjectKeys,
                imageBase64s: capturedImageBase64s,
                mimeType: capturedMimeType,
                telemetry: capturedTelemetry,
                context: context,
                clientScanId: capturedClientScanId,
                description: capturedDescription,
                observationContextJSON: capturedObservationContextJSON
            )
        }.value
        // Inference calls can take up to 25–30s on gemini-2.5-pro with slow connections.
        // Use a 90s timeout matching timeoutIntervalForResource to prevent false timeouts.
        let (data, _) = try await performAuthenticatedRequest(
            url: functionUrl,
            method: "POST",
            body: bodyData,
            timeoutInterval: 90.0,
            idempotencyKey: capturedClientScanId
        )
        return data
    }

    // MARK: - Multi-Modal Identification

    static func buildMultiModalRequestBody(
        r2ObjectKeys: [String] = [],
        audioR2ObjectKeys: [String] = [],
        videoR2ObjectKeys: [String] = [],
        base64ImageDatas: [String] = [],
        audioBase64s: [String] = [],
        videoFrameCount: Int? = nil,
        visualMediaItems: [IdentifyVisualMediaItem]? = nil,
        audioMediaItems: [IdentifyAudioMediaItem]? = nil,
        observationContextsJSON: [String] = [],
        userId: String,
        mimeType: String = "image/webp",
        telemetry: CaptureTelemetry,
        deviceLocale: String,
        deviceTimeZone: String,
        deviceRegion: String?,
        currentMonth: Int,
        timeOfDay: String,
        depthScaleText: String?,
        clientScanId: String,
        defaultGeoprivacy: String = "open",
        preferredGoal: FieldTripPreferredGoal? = nil
    ) throws -> Data {
        let context = InferenceRequestContext(
            userId: userId.lowercased(),
            deviceLocale: deviceLocale,
            deviceTimeZone: deviceTimeZone,
            deviceRegion: deviceRegion,
            currentMonth: currentMonth,
            timeOfDay: timeOfDay,
            depthScaleText: depthScaleText,
            defaultGeoprivacy: InferencePayloadBuilder.normalizedGeoprivacy(defaultGeoprivacy)
        )

        return try InferencePayloadBuilder.multimodalBody(
            r2ObjectKeys: r2ObjectKeys,
            audioR2ObjectKeys: audioR2ObjectKeys,
            videoR2ObjectKeys: videoR2ObjectKeys,
            imageBase64s: base64ImageDatas,
            audioBase64s: audioBase64s,
            videoFrameCount: videoFrameCount,
            visualMediaItems: visualMediaItems,
            audioMediaItems: audioMediaItems,
            observationContextsJSON: observationContextsJSON,
            mimeType: mimeType,
            telemetry: telemetry,
            context: context,
            clientScanId: clientScanId,
            preferredGoal: preferredGoal
        )
    }

    func buildMultiModalRequest(
        r2ObjectKeys: [String] = [],
        audioR2ObjectKeys: [String] = [],
        videoR2ObjectKeys: [String] = [],
        base64ImageDatas: [String] = [],
        mimeType: String = "image/webp",
        audioFilePaths: [String] = [],
        videoFrameCount: Int? = nil,
        visualMediaItems: [IdentifyVisualMediaItem]? = nil,
        audioMediaItems: [IdentifyAudioMediaItem]? = nil,
        observationContextsJSON: [String] = [],
        telemetry: CaptureTelemetry,
        clientScanId: String,
        preferredGoal: FieldTripPreferredGoal? = nil
    ) async throws -> URLRequest {
        let functionUrl = try endpointURL("identify-multimodal")
        let context = await makeInferenceRequestContext(telemetry: telemetry)
        let capturedR2ObjectKeys = r2ObjectKeys
        let capturedBase64ImageDatas = base64ImageDatas
        let capturedClientScanId = clientScanId

        let capturedAudioPaths = audioFilePaths
        let capturedAudioR2ObjectKeys = audioR2ObjectKeys
        let capturedVideoR2ObjectKeys = videoR2ObjectKeys
        let capturedVideoFrameCount = videoFrameCount
        let capturedVisualMediaItems = visualMediaItems
        let capturedAudioMediaItems = audioMediaItems
        let capturedContextsJSON = observationContextsJSON
        let capturedTelemetry = telemetry
        let capturedMimeType = mimeType
        let capturedPreferredGoal = preferredGoal

        let bodyData = try await Task.detached(priority: .userInitiated) {
            let audioBase64s = try MerianNetworkClient.loadInlineAudioBase64s(from: capturedAudioPaths)
            return try MerianNetworkClient.buildMultiModalRequestBody(
                r2ObjectKeys: capturedR2ObjectKeys,
                audioR2ObjectKeys: capturedAudioR2ObjectKeys,
                videoR2ObjectKeys: capturedVideoR2ObjectKeys,
                base64ImageDatas: capturedBase64ImageDatas,
                audioBase64s: audioBase64s,
                videoFrameCount: capturedVideoFrameCount,
                visualMediaItems: capturedVisualMediaItems,
                audioMediaItems: capturedAudioMediaItems,
                observationContextsJSON: capturedContextsJSON,
                userId: context.userId,
                mimeType: capturedMimeType,
                telemetry: capturedTelemetry,
                deviceLocale: context.deviceLocale,
                deviceTimeZone: context.deviceTimeZone,
                deviceRegion: context.deviceRegion,
                currentMonth: context.currentMonth,
                timeOfDay: context.timeOfDay,
                depthScaleText: context.depthScaleText,
                clientScanId: capturedClientScanId,
                defaultGeoprivacy: context.defaultGeoprivacy,
                preferredGoal: capturedPreferredGoal
            )
        }.value

        return try await makeAuthenticatedJSONRequest(
            url: functionUrl,
            bodyData: bodyData,
            idempotencyKey: capturedClientScanId
        )
    }

    /// Validates that the combined base64 image + audio payload fits the V8 isolator memory budget.
    /// Exposed as `internal` so test targets can exercise budget boundaries without auth dependencies.
    static let maxInlineInferenceBodyBytes = 3_600_000

    static func validateMultiModalPayloadBudget(imageBase64s: [String], audioBase64s: [String]) throws {
        let totalSize = (imageBase64s + audioBase64s).reduce(0) { $0 + $1.utf8.count }
        if totalSize > maxInlineInferenceBodyBytes {
            throw MerianError.payloadTooLarge
        }
    }

    static let maxInlineAudioBytes = MerianConfig.audioPayloadMaxBytes

    private static func loadInlineAudioBase64s(from audioFilePaths: [String]) throws -> [String] {
        guard !audioFilePaths.isEmpty else { return [] }

        let fileURLs = audioFilePaths.map { URL.documentsDirectory.appendingPathComponent($0) }
        try validateInlineAudioFileBudget(fileURLs: fileURLs)

        var audioBase64s: [String] = []
        audioBase64s.reserveCapacity(audioFilePaths.count)

        for url in fileURLs {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            let wavData = try Data(contentsOf: url, options: [.mappedIfSafe])
            audioBase64s.append(wavData.base64EncodedString())
        }

        return audioBase64s
    }

    static func validateInlineAudioFileBudget(fileURLs: [URL]) throws {
        var totalAudioBytes = 0
        for url in fileURLs {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            totalAudioBytes += try audioFileSize(at: url)
            guard totalAudioBytes <= maxInlineAudioBytes else {
                throw MerianError.payloadTooLarge
            }
        }
    }

    private static func audioFileSize(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? NSNumber {
            return size.intValue
        }
        throw MerianError.invalidResponse
    }

    func identifyMultiModal(
        r2ObjectKeys: [String] = [],
        base64ImageDatas: [String] = [],
        mimeType: String = "image/webp",
        audioFilePaths: [String] = [],
        videoR2ObjectKeys: [String] = [],
        videoFrameCount: Int? = nil,
        visualMediaItems: [IdentifyVisualMediaItem]? = nil,
        audioMediaItems: [IdentifyAudioMediaItem]? = nil,
        observationContextsJSON: [String] = [],
        telemetry: CaptureTelemetry,
        clientScanId: String? = nil,
        preferredGoal: FieldTripPreferredGoal? = nil,
        onRequestBodySent: (@Sendable () -> Void)? = nil
    ) async throws -> Data {
        let request = try await buildMultiModalRequest(
            r2ObjectKeys: r2ObjectKeys,
            videoR2ObjectKeys: videoR2ObjectKeys,
            base64ImageDatas: base64ImageDatas,
            mimeType: mimeType,
            audioFilePaths: audioFilePaths,
            videoFrameCount: videoFrameCount,
            visualMediaItems: visualMediaItems,
            audioMediaItems: audioMediaItems,
            observationContextsJSON: observationContextsJSON,
            telemetry: telemetry,
            clientScanId: clientScanId ?? UUID().uuidString.lowercased(),
            preferredGoal: preferredGoal
        )

        guard let url = request.url, let bodyData = request.httpBody else {
            throw MerianError.invalidURL
        }

        let (data, _) = try await performAuthenticatedRequest(
            url: url,
            method: "POST",
            body: bodyData,
            timeoutInterval: 90.0,
            idempotencyKey: request.value(forHTTPHeaderField: "Idempotency-Key"),
            onRequestBodySent: onRequestBodySent
        )
        return data
    }

    func updateDeferredScanContext(scanId: String, telemetry: CaptureTelemetry) async throws {
        let functionUrl = try endpointURL("update-scan-context")
        var payload: [String: Any] = ["scan_id": scanId]
        if let gpsElevation = telemetry.gpsElevation {
            payload["gps_elevation"] = gpsElevation
        }
        if let condition = telemetry.weatherCondition {
            payload["weather_condition"] = condition
        }
        if let temperature = telemetry.weatherTemperatureF {
            payload["weather_temperature_f"] = temperature
        }
        if let locationName = telemetry.locationName {
            payload["semantic_location"] = locationName
        }
        guard payload.count > 1 else { return }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        _ = try await performAuthenticatedRequest(
            url: functionUrl,
            method: "POST",
            body: bodyData,
            timeoutInterval: 15
        )
    }

    func fetchEnrichment(
        scanId: String,
        scientificName: String,
        confidenceScore: Double,
        inferenceTier: String,
        scope: String
    ) async throws -> EnrichScanResponse {
        let functionUrl = try endpointURL("enrich-scan")
        let payload: [String: Any] = [
            "scan_id": scanId,
            "scientific_name": scientificName,
            "confidence_score": confidenceScore,
            "inference_tier": inferenceTier,
            "scope": scope
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        // Scan IDs are UUIDs and remain stable across foreground, offline, and
        // server-recovery retries. The database namespaces idempotency by
        // operation, so enrichment and lookalike calls can safely share it.
        guard let idempotencyKey = UUID(uuidString: scanId)?.uuidString.lowercased() else {
            throw MerianError.invalidResponse
        }
        let (data, _) = try await performAuthenticatedRequest(
            url: functionUrl,
            method: "POST",
            body: bodyData,
            idempotencyKey: idempotencyKey
        )
        return try JSONDecoder().decode(EnrichScanResponse.self, from: data)
    }

    // MARK: - R2 Storage

    func generateUploadURLs(uploadFiles: [StagingUploadFile]) async throws -> [PreSignedURL] {
        let functionUrl = try endpointURL("generate-upload-urls")
        let authUserId = try? await SupabaseManager.shared.client.auth.session.user.id.uuidString
        let deviceId = await MainActor.run { DeviceIdentityManager.shared.deviceId }
        let userId = (authUserId ?? deviceId).lowercased()
        let bodyData = try JSONEncoder().encode(UploadURLRequestBody(files: uploadFiles, userId: userId))

        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try JSONDecoder().decode(PreSignedURLResponse.self, from: data).urls
    }

    func generateUploadURLs(fileNames: [String]) async throws -> [PreSignedURL] {
        let functionUrl = try endpointURL("generate-upload-urls")
        let authUserId = try? await SupabaseManager.shared.client.auth.session.user.id.uuidString
        let deviceId = await MainActor.run { DeviceIdentityManager.shared.deviceId }
        let userId = (authUserId ?? deviceId).lowercased()
        let payload: [String: Any] = ["fileNames": fileNames, "user_id": userId]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try JSONDecoder().decode(PreSignedURLResponse.self, from: data).urls
    }

    func uploadToR2(url: String, data: Data, mimeType: String = "image/webp") async throws {
        guard let signedUrl = URL(string: url) else { throw MerianError.invalidURL }

        var request = URLRequest(url: signedUrl)
        request.httpMethod = "PUT"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let uploadStart = CFAbsoluteTimeGetCurrent()
        let (responseData, response) = try await activeSession.data(for: request)
        MerianLog.network.debug("R2 upload completed in \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - uploadStart), privacy: .public)s.")
        try validateR2UploadResponse(responseData: responseData, response: response)
    }

    func uploadToR2(url: String, fileURL: URL, mimeType: String = "image/webp") async throws {
        guard let signedUrl = URL(string: url) else { throw MerianError.invalidURL }

        var request = URLRequest(url: signedUrl)
        request.httpMethod = "PUT"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")

        let uploadStart = CFAbsoluteTimeGetCurrent()
        let (responseData, response) = try await activeSession.upload(for: request, fromFile: fileURL)
        MerianLog.network.debug("R2 file upload completed in \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - uploadStart), privacy: .public)s.")
        try validateR2UploadResponse(responseData: responseData, response: response)
    }

    func inspectScanImageCloudStatus(sourceUrl: String) async throws -> ScanImageCloudInspection {
        try await scanImageCloudRequest(sourceUrl: sourceUrl, restoredObjectKey: nil)
    }

    func repairScanImageCloudReference(
        sourceUrl: String,
        restoredObjectKey: String
    ) async throws -> ScanImageCloudInspection {
        try await scanImageCloudRequest(
            sourceUrl: sourceUrl,
            restoredObjectKey: restoredObjectKey
        )
    }

    private func scanImageCloudRequest(
        sourceUrl: String,
        restoredObjectKey: String?
    ) async throws -> ScanImageCloudInspection {
        let functionUrl = try endpointURL("repair-scan-image")
        var payload: [String: Any] = ["source_url": sourceUrl]
        if let restoredObjectKey {
            payload["restored_object_key"] = restoredObjectKey
        }
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(
            url: functionUrl,
            method: "POST",
            body: bodyData
        )
        return try JSONDecoder()
            .decode(ScanImageCloudInspectionResponse.self, from: data)
            .data
    }

    func uploadStagedVideoFiles(videoFilePaths: [String], scanId: String) async throws -> [String] {
        var videoFileURLs: [URL] = []
        var missingVideoPaths: [String] = []
        for videoFilePath in videoFilePaths {
            if let fileURL = existingLocalMediaURL(for: videoFilePath) {
                videoFileURLs.append(fileURL)
            } else {
                missingVideoPaths.append(videoFilePath)
            }
        }

        guard !videoFileURLs.isEmpty else {
            MerianLog.network.error("Video staging upload requested but no local video files were found.")
            throw CocoaError(.fileNoSuchFile)
        }
        if !missingVideoPaths.isEmpty {
            MerianLog.network.error(
                "Video staging upload missing \(missingVideoPaths.count, privacy: .public)/\(videoFilePaths.count, privacy: .public) requested local video file(s)."
            )
            throw CocoaError(.fileNoSuchFile)
        }

        let uploadFiles = try videoFileURLs.map { fileURL in
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let sizeBytes = (attributes[.size] as? NSNumber)?.intValue
            return StagingUploadFile(
                fileName: MediaStagingContract.stagingFileName(scanId: scanId, localPath: fileURL.lastPathComponent),
                mediaKind: .video,
                contentType: StagedMediaKind.video.contentType(for: fileURL.path),
                sizeBytes: sizeBytes,
                clientScanId: scanId,
                mediaRole: StagedMediaKind.video.defaultScanMediaRole
            )
        }

        guard uploadFiles.count <= MerianConfig.mediaStagingMaxVideoFilesPerRequest,
              uploadFiles.count <= MerianConfig.mediaStagingMaxFilesPerRequest else {
            throw MerianError.payloadTooLarge
        }
        for uploadFile in uploadFiles {
            if let sizeBytes = uploadFile.sizeBytes,
               sizeBytes > MerianConfig.videoPayloadMaxBytes {
                throw MerianError.payloadTooLarge
            }
        }

        let uploadURLs = try await generateUploadURLs(uploadFiles: uploadFiles)
        guard uploadURLs.count == videoFileURLs.count else {
            throw MerianError.invalidResponse
        }

        for (fileURL, uploadURL) in zip(videoFileURLs, uploadURLs) {
            try await uploadToR2(
                url: uploadURL.signedUrl,
                fileURL: fileURL,
                mimeType: StagedMediaKind.video.contentType(for: fileURL.path)
            )
        }

        return uploadURLs.map(\.objectKey)
    }

    private func resolvedLocalMediaURL(for path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("file://"), let url = URL(string: trimmed), url.isFileURL {
            return url
        }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }
        return URL.documentsDirectory.appendingPathComponent(trimmed)
    }

    private func existingLocalMediaURL(for path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let primaryURL = resolvedLocalMediaURL(for: trimmed)
        if FileManager.default.fileExists(atPath: primaryURL.path) {
            return primaryURL
        }

        let fileName = primaryURL.lastPathComponent
        guard !fileName.isEmpty else { return nil }

        let fallbackURLs = [
            URL.documentsDirectory.appendingPathComponent(fileName),
            FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        ]
        return fallbackURLs.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func validateR2UploadResponse(responseData: Data, response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MerianError.uploadFailed
        }

        if httpResponse.statusCode != 200 {
            let errString = String(data: responseData, encoding: .utf8) ?? "Unknown"
            MerianLog.network.debug("R2 upload failed [\(httpResponse.statusCode, privacy: .public)]: \(errString, privacy: .public)")
            throw MerianError.uploadFailed
        }
    }

    // MARK: - Outbox Confirmation

    /// Asks the server whether `scanId` exists in `public.scans` for the current user.
    /// Returns the compatibility status plus optional scan-ingestion job state for recovery.
    func checkScanStatusDetails(
        scanId: String,
        requiredVideoCount: Int? = nil,
        recoveryScan: OwnedScanRecoveryPayload? = nil
    ) async throws -> ScanStatusResponse {
        let functionUrl = try endpointURL("check-scan-status")
        var payload: [String: Any] = ["scan_id": scanId]
        if let requiredVideoCount, requiredVideoCount > 0 {
            payload["required_video_count"] = requiredVideoCount
        }
        if let recoveryScan {
            let recoveryData = try JSONEncoder().encode(recoveryScan)
            guard let recoveryObject = try JSONSerialization.jsonObject(with: recoveryData) as? [String: Any] else {
                throw MerianError.invalidResponse
            }
            payload["recovery_scan"] = recoveryObject
        }
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        let decoded: ScanStatusResponse
        do {
            decoded = try JSONDecoder().decode(
                ScanStatusResponse.self,
                from: data
            )
        } catch {
            throw MerianError.invalidResponse
        }
        guard decoded.scanId == nil ||
                decoded.scanId?.caseInsensitiveCompare(scanId) == .orderedSame,
              decoded.jobAttemptCount.map({ $0 >= 0 }) ?? true else {
            throw MerianError.invalidResponse
        }
        return decoded
    }

    func checkScanStatuses(_ requirements: [String: Int]) async throws -> [String: ScanStatusResponse] {
        guard !requirements.isEmpty else { return [:] }
        var expectedScanIds: [String: String] = [:]
        for scanId in requirements.keys {
            let normalized = scanId
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !normalized.isEmpty,
                  expectedScanIds.updateValue(
                    scanId,
                    forKey: normalized
                  ) == nil else {
                throw MerianError.invalidResponse
            }
        }
        let functionUrl = try endpointURL("check-scan-status")
        let scans = requirements.map { requirement in
            var payload: [String: Any] = ["scan_id": requirement.key]
            let requiredVideoCount = requirement.value
            if requiredVideoCount > 0 {
                payload["required_video_count"] = requiredVideoCount
            }
            return payload
        }
        let bodyData = try JSONSerialization.data(withJSONObject: ["scans": scans])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        let decoded: BulkScanStatusResponse
        do {
            decoded = try JSONDecoder().decode(
                BulkScanStatusResponse.self,
                from: data
            )
        } catch {
            throw MerianError.invalidResponse
        }
        guard decoded.results.count == expectedScanIds.count else {
            throw MerianError.invalidResponse
        }

        var results: [String: ScanStatusResponse] = [:]
        for result in decoded.results {
            guard let returnedScanId = result.scanId?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                let requestedScanId = expectedScanIds[
                    returnedScanId.lowercased()
                ],
                results[requestedScanId] == nil,
                result.jobAttemptCount.map({ $0 >= 0 }) ?? true else {
                throw MerianError.invalidResponse
            }
            results[requestedScanId] = result
        }
        guard results.count == expectedScanIds.count else {
            throw MerianError.invalidResponse
        }
        return results
    }

    /// Compatibility wrapper for older call sites that only need `"found"` / `"not_found"`.
    func checkScanStatus(scanId: String, requiredVideoCount: Int? = nil) async throws -> String {
        let response = try await checkScanStatusDetails(
            scanId: scanId,
            requiredVideoCount: requiredVideoCount
        )
        return response.status.rawValue
    }

    // MARK: - Data Mutation

    func deleteScan(scanId: String) async throws {
        let functionUrl = try endpointURL("delete-scan")
        let bodyData = try JSONSerialization.data(withJSONObject: ["scanId": scanId])
        let (data, _) = try await performAuthenticatedRequest(
            url: functionUrl,
            method: "POST",
            body: bodyData
        )
        let response: DeleteScanResponse
        do {
            response = try JSONDecoder().decode(DeleteScanResponse.self, from: data)
        } catch {
            throw MerianError.invalidResponse
        }
        guard response.success else {
            throw MerianError.invalidResponse
        }
        MerianLog.network.debug("Scan deleted: \(scanId, privacy: .private)")
    }

    func safeDeleteAccount() async throws {
        let functionUrl = try endpointURL("safe-delete")
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST")
        MerianLog.network.debug("Account deletion accepted.")
    }

    // MARK: - Darwin Core Export

    /// Queues a DwC-A export job. The insertion transaction snapshots bounded
    /// source membership and revision fingerprints, then a background webhook
    /// generates the ZIP and emails the final download link via Resend.
    func requestDwcAExport(scope: String = "personal") async throws {
        let functionUrl = try endpointURL("request-export-dwca")
        // includePreciseCoordinates: true — intentional for personal exports. The requesting
        // user is downloading their own data, so full-resolution GPS coordinates are appropriate.
        // For "global" scope exports, the server scrubs coordinates for all rows except the
        // requesting user's own records, regardless of this flag.
        let payload: [String: Any] = ["exportScope": scope, "includePreciseCoordinates": true]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)

        // Archive generation remains asynchronous; this timeout covers only the
        // bounded queue-and-snapshot transaction.
        _ = try await performAuthenticatedRequest(
            url: functionUrl,
            method: "POST",
            body: bodyData,
            timeoutInterval: 15.0
        )
    }

    // MARK: - Explore

    func getExploreFeed(
        limit: Int = 20,
        filter: ExploreFeedFilter = .recent,
        latitude: Double? = nil,
        longitude: Double? = nil,
        cursor: ExploreFeedCursor? = nil,
        advancedFilters: ExploreFeedAdvancedFilters = ExploreFeedAdvancedFilters(),
        sharedSince: Date? = nil
    ) async throws -> [ExplorePost] {
        let functionUrl = try endpointURL("get-explore-feed")
        var payload: [String: Any] = [
            "limit": limit,
            "filter": filter.rawValue
        ]

        if let latitude {
            payload["latitude"] = latitude
        }

        if let longitude {
            payload["longitude"] = longitude
        }

        if !advancedFilters.speciesCategories.isEmpty {
            payload["species_categories"] = advancedFilters.speciesCategories
                .sorted { $0.sortPriority < $1.sortPriority }
                .map(\.rawValue)
        }

        if !advancedFilters.mediaTypes.isEmpty {
            payload["media_types"] = advancedFilters.mediaTypes
                .map(\.rawValue)
                .sorted()
        }

        if let sharedSince {
            payload["shared_since"] = DateUtilities.iso8601Formatter.string(from: sharedSince)
        }

        if filter == .nearby {
            payload["nearby_radius_miles"] = advancedFilters.nearbyRadius.rawValue
        }

        if let cursor {
            if let beforeSharedAt = cursor.beforeSharedAt,
               let beforePostId = cursor.beforePostId {
                payload["before_shared_at"] = beforeSharedAt
                payload["before_post_id"] = beforePostId
            }

            if let beforeRankingValue = cursor.beforeRankingValue {
                payload["before_ranking_value"] = beforeRankingValue
            }
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreFeedResponse.self, from: data).data
    }

    func getCommunityIdentificationFeed(
        limit: Int = 30,
        scope: CommunityIdentificationFeedScope = .all,
        group: CommunityIdentificationRequestGroup = .all,
        latitude: Double? = nil,
        longitude: Double? = nil,
        cursor: CommunityIdentificationCursor? = nil
    ) async throws -> [CommunityIdentificationFeedItem] {
        let functionUrl = try endpointURL("get-community-identification-feed")
        var payload: [String: Any] = [
            "limit": limit,
            "scope": scope.rawValue,
            "group": group.rawValue
        ]

        if let latitude {
            payload["latitude"] = latitude
        }

        if let longitude {
            payload["longitude"] = longitude
        }

        if let cursor,
           let beforeRequestedAt = cursor.beforeRequestedAt,
           let beforeRequestId = cursor.beforeRequestId {
            payload["before_requested_at"] = beforeRequestedAt
            payload["before_request_id"] = beforeRequestId
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(CommunityIdentificationFeedResponse.self, from: data).data
    }

    func getCommunityIdentificationDetail(requestId: String) async throws -> CommunityIdentificationDetail {
        let functionUrl = try endpointURL("get-community-identification-detail")
        let payload: [String: Any] = ["request_id": requestId]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(CommunityIdentificationDetailResponse.self, from: data).data
    }

    func updateCommunityIdentificationRequest(
        requestId: String,
        note: String?,
        locationSharing: ExplorePostLocationSharing
    ) async throws -> CommunityRequestUpdate {
        let functionUrl = try endpointURL("update-community-identification-request")
        let payload: [String: Any] = [
            "request_id": requestId,
            "note": note ?? NSNull(),
            "location_sharing": locationSharing.rawValue
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(CommunityRequestUpdateResponse.self, from: data).data
    }

    func searchCommunityTaxa(
        query: String,
        limit: Int = 20,
        taxonomyVersionId: String? = nil
    ) async throws -> [CommunityTaxonSearchResult] {
        let functionUrl = try endpointURL("search-community-taxa")
        var payload: [String: Any] = [
            "query": query,
            "limit": limit
        ]
        if let taxonomyVersionId {
            payload["taxonomy_version_id"] = taxonomyVersionId
        }
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(CommunityTaxonSearchResponse.self, from: data).data
    }

    func submitCommunityIdentification(
        requestId: String,
        taxonId: String,
        disagreementMode: CommunityIdentificationDisagreementMode,
        reasoning: String?,
        isGenusBestPossible: Bool
    ) async throws -> CommunityIdentificationMutation {
        let functionUrl = try endpointURL("submit-community-identification")
        var payload: [String: Any] = [
            "request_id": requestId,
            "taxon_id": taxonId,
            "disagreement_mode": disagreementMode.rawValue,
            "is_genus_best_possible": isGenusBestPossible
        ]
        payload["reasoning"] = reasoning ?? NSNull()
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(CommunityIdentificationMutationResponse.self, from: data).data
    }

    func withdrawCommunityIdentification(identificationId: String) async throws -> CommunityIdentificationMutation {
        let functionUrl = try endpointURL("withdraw-community-identification")
        let payload: [String: Any] = ["identification_id": identificationId]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(CommunityIdentificationMutationResponse.self, from: data).data
    }

    func restoreCommunityIdentification(identificationId: String) async throws -> CommunityIdentificationMutation {
        let functionUrl = try endpointURL("restore-community-identification")
        let payload: [String: Any] = ["identification_id": identificationId]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(CommunityIdentificationMutationResponse.self, from: data).data
    }

    func getExploreMapPoints(
        northLatitude: Double,
        southLatitude: Double,
        eastLongitude: Double,
        westLongitude: Double,
        zoomLevel: Double,
        limit: Int = 500,
        speciesCategories: Set<ExploreMapSpeciesCategory> = [],
        mediaTypes: Set<ExploreMediaKind> = []
    ) async throws -> ExploreMapPointsResponse {
        let functionUrl = try endpointURL("get-explore-map-points")
        var payload: [String: Any] = [
            "north_latitude": northLatitude,
            "south_latitude": southLatitude,
            "east_longitude": eastLongitude,
            "west_longitude": westLongitude,
            "zoom_level": zoomLevel,
            "limit": limit
        ]
        if !speciesCategories.isEmpty {
            payload["species_categories"] = speciesCategories.map(\.rawValue).sorted()
        }
        if !mediaTypes.isEmpty {
            payload["media_types"] = mediaTypes.map(\.rawValue).sorted()
        }
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreMapPointsResponse.self, from: data)
    }

    func getExploreComments(
        postId: String,
        limit: Int = 100,
        afterCreatedAt: String? = nil,
        afterCommentId: String? = nil
    ) async throws -> [ExploreComment] {
        let functionUrl = try endpointURL("get-explore-comments")
        var payload: [String: Any] = [
            "post_id": postId,
            "limit": limit
        ]

        if let afterCreatedAt, let afterCommentId {
            payload["after_created_at"] = afterCreatedAt
            payload["after_comment_id"] = afterCommentId
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreCommentsResponse.self, from: data).data
    }

    func getExploreCommentReplies(
        parentCommentId: String,
        limit: Int = 25,
        afterCreatedAt: String? = nil,
        afterCommentId: String? = nil
    ) async throws -> [ExploreComment] {
        let functionUrl = try endpointURL("get-explore-comment-replies")
        var payload: [String: Any] = [
            "parent_comment_id": parentCommentId,
            "limit": limit
        ]

        if let afterCreatedAt, let afterCommentId {
            payload["after_created_at"] = afterCreatedAt
            payload["after_comment_id"] = afterCommentId
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreCommentsResponse.self, from: data).data
    }

    func getExploreMentionSuggestions(
        postId: String,
        parentCommentId: String? = nil,
        query: String,
        limit: Int = 8
    ) async throws -> [ExploreMentionSuggestion] {
        let functionUrl = try endpointURL("get-explore-mention-suggestions")
        var payload: [String: Any] = [
            "post_id": postId,
            "query": query,
            "limit": limit
        ]
        if let parentCommentId {
            payload["parent_comment_id"] = parentCommentId
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreMentionSuggestionsResponse.self, from: data).data
    }

    func getExplorePost(postId: String) async throws -> ExplorePost {
        let functionUrl = try endpointURL("get-explore-post")
        let bodyData = try JSONSerialization.data(withJSONObject: ["post_id": postId])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExplorePostResponse.self, from: data).data
    }

    func getExploreComposerMedia(scanId: String? = nil, postId: String? = nil) async throws -> ExploreComposerMediaPayload {
        let functionUrl = try endpointURL("get-explore-composer-media")
        var payload: [String: Any] = [:]
        if let scanId {
            payload["scan_id"] = scanId
        }
        if let postId {
            payload["post_id"] = postId
        }
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreComposerMediaResponse.self, from: data).data
    }

    func getExplorePostDetail(postId: String) async throws -> ExplorePostDetail {
        let functionUrl = try endpointURL("get-explore-post-detail")
        let bodyData = try JSONSerialization.data(withJSONObject: ["post_id": postId])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExplorePostDetailResponse.self, from: data).data
    }

    func getSpeciesDictionary(scientificName: String) async throws -> SpeciesDictionaryEntry {
        try await performSpeciesDictionaryRequest(speciesId: nil, scientificName: scientificName)
    }

    func getSpeciesDictionary(speciesId: String, scientificName: String? = nil) async throws -> SpeciesDictionaryEntry {
        try await performSpeciesDictionaryRequest(speciesId: speciesId, scientificName: scientificName)
    }

    func getSpeciesDictionaryCatalog(
        category: SpeciesDictionaryCatalogCategory = .all,
        region: String? = nil,
        group: String? = nil,
        query: String? = nil,
        limit: Int = 40,
        cursor: SpeciesDictionaryCatalogCursor? = nil
    ) async throws -> SpeciesDictionaryCatalogResponse {
        let functionUrl = try endpointURL("species-dictionary")
        var payload: [String: Any] = [
            "mode": "catalog",
            "limit": limit
        ]
        if category != .all {
            payload["category"] = category.rawValue
        }
        if let region = region?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            payload["region"] = region
        }
        if let group = group?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            payload["group"] = group
        }
        if let query = query?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            payload["query"] = query
        }
        if let cursor {
            var cursorPayload: [String: Any] = [
                "scientific_name": cursor.scientificName,
                "species_id": cursor.speciesId
            ]
            if let createdAt = cursor.createdAt {
                cursorPayload["created_at"] = createdAt
            }
            payload["cursor"] = cursorPayload
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(SpeciesDictionaryCatalogResponse.self, from: data)
    }

    func getSpeciesDictionaryCatalog(
        query: String? = nil,
        limit: Int = 40,
        cursor: SpeciesDictionaryCatalogCursor? = nil
    ) async throws -> SpeciesDictionaryCatalogResponse {
        try await getSpeciesDictionaryCatalog(
            category: .all,
            region: nil,
            group: nil,
            query: query,
            limit: limit,
            cursor: cursor
        )
    }

    func getSpeciesDictionaryOverview(userRegion: String? = nil) async throws -> SpeciesDictionaryOverviewResponse {
        let functionUrl = try endpointURL("species-dictionary")
        var payload: [String: Any] = [
            "mode": "overview",
            "cache_buster": UUID().uuidString
        ]
        if let userRegion = userRegion?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            payload["user_region"] = userRegion
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(SpeciesDictionaryOverviewResponse.self, from: data)
    }

    func getSpeciesDictionaryTree(
        scope: SpeciesDictionaryTreeScope = .allSpecies
    ) async throws -> SpeciesDictionaryTreeResponse {
        let functionUrl = try endpointURL("species-dictionary")
        let payload: [String: Any] = [
            "mode": "tree",
            "scope": scope.rawValue
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(SpeciesDictionaryTreeResponse.self, from: data)
    }

    func getSpeciesObservationStats(
        speciesId: String,
        scientificName: String
    ) async throws -> SpeciesObservationStatsEntry {
        let functionUrl = try endpointURL("species-observation-stats")
        guard
            let normalizedSpeciesId = normalizedSpeciesDictionaryId(speciesId),
            let speciesUUID = UUID(uuidString: normalizedSpeciesId)
        else {
            throw MerianError.invalidResponse
        }
        let requestedSpeciesId = speciesUUID.uuidString.lowercased()
        let normalizedScientificName = scientificName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard
            let requestedScientificName = normalizedScientificName.nilIfEmpty,
            requestedScientificName.count <= 160
        else {
            throw MerianError.invalidResponse
        }

        if let cached = cachedSpeciesObservationStatsEntry(
            speciesId: requestedSpeciesId,
            scientificName: requestedScientificName
        ) {
            return cached
        }

        var components = URLComponents(url: functionUrl, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "species_id", value: requestedSpeciesId),
            URLQueryItem(name: "scientific_name", value: requestedScientificName)
        ]
        guard let requestURL = components?.url else {
            throw MerianError.invalidURL
        }

        let (data, _) = try await performAuthenticatedRequest(
            url: requestURL,
            method: "GET",
            timeoutInterval: 20.0
        )
        let response = try makeExploreDecoder().decode(SpeciesObservationStatsResponse.self, from: data)
        let entry = response.data
        guard
            response.effectiveSchemaVersion >= 2,
            normalizedSpeciesDictionaryId(entry.speciesId) == requestedSpeciesId,
            normalizedSpeciesDictionaryName(entry.scientificName) ==
                normalizedSpeciesDictionaryName(requestedScientificName)
        else {
            throw MerianError.invalidResponse
        }
        cacheSpeciesObservationStatsEntry(
            entry,
            requestedSpeciesId: requestedSpeciesId,
            requestedScientificName: requestedScientificName
        )
        return entry
    }

    private func performSpeciesDictionaryRequest(speciesId: String?, scientificName: String?) async throws -> SpeciesDictionaryEntry {
        let functionUrl = try endpointURL("species-dictionary")
        var payload: [String: Any] = [:]
        let requestedSpeciesId = speciesId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let requestedScientificName = scientificName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        if let cached = cachedSpeciesDictionaryEntry(
            speciesId: requestedSpeciesId,
            scientificName: requestedScientificName
        ) {
            return cached
        }

        if let speciesId = requestedSpeciesId {
            payload["species_id"] = speciesId
        }
        if let scientificName = requestedScientificName {
            payload["scientific_name"] = scientificName
        }
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        let entry = try makeExploreDecoder().decode(SpeciesDictionaryResponse.self, from: data).data
        cacheSpeciesDictionaryEntry(
            entry,
            requestedSpeciesId: requestedSpeciesId,
            requestedScientificName: requestedScientificName
        )
        return entry
    }

    private func cachedSpeciesDictionaryEntry(
        speciesId: String?,
        scientificName: String?
    ) -> SpeciesDictionaryEntry? {
        guard let key = speciesDictionaryCacheKey(
            speciesId: speciesId,
            scientificName: scientificName
        ) else {
            return nil
        }

        speciesDictionaryCacheLock.lock()
        defer { speciesDictionaryCacheLock.unlock() }

        guard let cached = speciesDictionaryCache[key] else { return nil }
        guard Date().timeIntervalSince(cached.storedAt) < speciesDictionaryCacheTTL else {
            speciesDictionaryCache.removeValue(forKey: key)
            return nil
        }

        return cached.value
    }

    private func cacheSpeciesDictionaryEntry(
        _ entry: SpeciesDictionaryEntry,
        requestedSpeciesId: String?,
        requestedScientificName: String?
    ) {
        let keys = speciesDictionaryCacheKeys(
            for: entry,
            requestedSpeciesId: requestedSpeciesId,
            requestedScientificName: requestedScientificName
        )
        guard !keys.isEmpty else { return }

        let now = Date()
        speciesDictionaryCacheLock.lock()
        defer { speciesDictionaryCacheLock.unlock() }

        for key in keys {
            speciesDictionaryCache[key] = SpeciesDictionaryCacheEntry(
                value: entry,
                storedAt: now
            )
        }

        if speciesDictionaryCache.count > speciesDictionaryCacheLimit {
            let expiredKeys = speciesDictionaryCache
                .filter { now.timeIntervalSince($0.value.storedAt) >= speciesDictionaryCacheTTL }
                .map(\.key)
            for key in expiredKeys {
                speciesDictionaryCache.removeValue(forKey: key)
            }

            if speciesDictionaryCache.count > speciesDictionaryCacheLimit {
                let currentOverflowCount = speciesDictionaryCache.count - speciesDictionaryCacheLimit
                let keysToRemove = speciesDictionaryCache
                    .sorted { $0.value.storedAt < $1.value.storedAt }
                    .prefix(currentOverflowCount)
                    .map(\.key)
                for key in keysToRemove {
                    speciesDictionaryCache.removeValue(forKey: key)
                }
            }
        }
    }

    private func speciesDictionaryCacheKey(
        speciesId: String?,
        scientificName: String?
    ) -> String? {
        if let speciesId = normalizedSpeciesDictionaryId(speciesId) {
            return "id:\(speciesId)"
        }
        if let scientificName = normalizedSpeciesDictionaryName(scientificName) {
            return "name:\(scientificName)"
        }
        return nil
    }

    private func cachedSpeciesObservationStatsEntry(
        speciesId: String?,
        scientificName: String?
    ) -> SpeciesObservationStatsEntry? {
        guard let key = speciesDictionaryCacheKey(
            speciesId: speciesId,
            scientificName: scientificName
        ) else {
            return nil
        }

        speciesObservationStatsCacheLock.lock()
        defer { speciesObservationStatsCacheLock.unlock() }

        guard let cached = speciesObservationStatsCache[key] else { return nil }
        guard Date().timeIntervalSince(cached.storedAt) < speciesObservationStatsCacheTTL else {
            speciesObservationStatsCache.removeValue(forKey: key)
            return nil
        }

        return cached.value
    }

    private func cacheSpeciesObservationStatsEntry(
        _ entry: SpeciesObservationStatsEntry,
        requestedSpeciesId: String?,
        requestedScientificName: String?
    ) {
        var keys = Set<String>()
        if let requestedSpeciesId = normalizedSpeciesDictionaryId(requestedSpeciesId) {
            keys.insert("id:\(requestedSpeciesId)")
        }
        if let entrySpeciesId = normalizedSpeciesDictionaryId(entry.speciesId) {
            keys.insert("id:\(entrySpeciesId)")
        }
        if let requestedScientificName = normalizedSpeciesDictionaryName(requestedScientificName) {
            keys.insert("name:\(requestedScientificName)")
        }
        if let entryScientificName = normalizedSpeciesDictionaryName(entry.scientificName) {
            keys.insert("name:\(entryScientificName)")
        }
        guard !keys.isEmpty else { return }

        let now = Date()
        speciesObservationStatsCacheLock.lock()
        defer { speciesObservationStatsCacheLock.unlock() }

        for key in keys {
            speciesObservationStatsCache[key] = SpeciesObservationStatsCacheEntry(
                value: entry,
                storedAt: now
            )
        }

        if speciesObservationStatsCache.count > speciesObservationStatsCacheLimit {
            let expiredKeys = speciesObservationStatsCache
                .filter { now.timeIntervalSince($0.value.storedAt) >= speciesObservationStatsCacheTTL }
                .map(\.key)
            for key in expiredKeys {
                speciesObservationStatsCache.removeValue(forKey: key)
            }

            if speciesObservationStatsCache.count > speciesObservationStatsCacheLimit {
                let currentOverflowCount = speciesObservationStatsCache.count - speciesObservationStatsCacheLimit
                let keysToRemove = speciesObservationStatsCache
                    .sorted { $0.value.storedAt < $1.value.storedAt }
                    .prefix(currentOverflowCount)
                    .map(\.key)
                for key in keysToRemove {
                    speciesObservationStatsCache.removeValue(forKey: key)
                }
            }
        }
    }

    private func speciesDictionaryCacheKeys(
        for entry: SpeciesDictionaryEntry,
        requestedSpeciesId: String?,
        requestedScientificName: String?
    ) -> Set<String> {
        var keys = Set<String>()
        if let requestedSpeciesId = normalizedSpeciesDictionaryId(requestedSpeciesId) {
            keys.insert("id:\(requestedSpeciesId)")
        }
        if let entrySpeciesId = normalizedSpeciesDictionaryId(entry.id) {
            keys.insert("id:\(entrySpeciesId)")
        }
        if let requestedScientificName = normalizedSpeciesDictionaryName(requestedScientificName) {
            keys.insert("name:\(requestedScientificName)")
        }
        if let entryScientificName = normalizedSpeciesDictionaryName(entry.scientificName) {
            keys.insert("name:\(entryScientificName)")
        }
        return keys
    }

    private func normalizedSpeciesDictionaryId(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .nilIfEmpty
    }

    private func normalizedSpeciesDictionaryName(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
            .nilIfEmpty
    }

    func getExploreAuthorProfile(authorUserId: String, previewLimit: Int = 9) async throws -> ExploreAuthorProfile {
        let functionUrl = try endpointURL("get-explore-author-profile")
        let bodyData = try JSONSerialization.data(withJSONObject: [
            "author_user_id": authorUserId,
            "preview_limit": previewLimit
        ])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreAuthorProfileResponse.self, from: data).data
    }

    func getExploreAuthorPosts(
        authorUserId: String,
        limit: Int = 30,
        cursor: ExploreAuthorPostCursor? = nil
    ) async throws -> ExploreAuthorPostsResponse {
        let functionUrl = try endpointURL("get-explore-author-posts")
        var payload: [String: Any] = [
            "author_user_id": authorUserId,
            "limit": limit
        ]

        if let cursor,
           let beforeSharedAt = cursor.beforeSharedAt,
           let beforePostId = cursor.beforePostId {
            payload["before_shared_at"] = beforeSharedAt
            payload["before_post_id"] = beforePostId
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreAuthorPostsResponse.self, from: data)
    }

    func getFieldTrips(userRegion: String? = nil, limit: Int = 40) async throws -> [FieldTripTemplate] {
        let functionUrl = try endpointURL("field-trips")
        var payload: [String: Any] = [
            "action": "catalog",
            "limit": limit
        ]
        if let userRegion = userRegion?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            payload["user_region"] = userRegion
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(FieldTripsCatalogResponse.self, from: data).data
    }

    func getFieldTripCaptureContext() async throws -> [FieldTripCaptureOuting] {
        let functionUrl = try endpointURL("field-trips")
        let bodyData = try JSONSerialization.data(withJSONObject: [
            "action": "capture_context"
        ])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(FieldTripCaptureContextResponse.self, from: data).data
    }

    func getFirstFieldTripAchievementProgress() async throws -> FirstFieldTripAchievementProgress? {
        let functionUrl = try endpointURL("field-trips")
        let bodyData = try JSONSerialization.data(withJSONObject: [
            "action": "achievement_progress"
        ])
        let (data, _) = try await performAuthenticatedRequest(
            url: functionUrl,
            method: "POST",
            body: bodyData
        )
        return try makeExploreDecoder().decode(
            FirstFieldTripAwardResponse.self,
            from: data
        ).data
    }

    func getFieldTripTemplate(templateId: String) async throws -> FieldTripTemplate {
        try await getFieldTripTemplate(identifier: ["template_id": templateId])
    }

    func getFieldTripTemplate(slug: String) async throws -> FieldTripTemplate {
        try await getFieldTripTemplate(identifier: ["slug": slug])
    }

    private func getFieldTripTemplate(identifier: [String: String]) async throws -> FieldTripTemplate {
        let functionUrl = try endpointURL("field-trips")
        var payload = identifier
        payload["action"] = "template_detail"
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(FieldTripTemplateDetailResponse.self, from: data).data
    }

    func startFieldTrip(templateId: String) async throws -> FieldTripTemplate {
        let functionUrl = try endpointURL("field-trips")
        let bodyData = try JSONSerialization.data(withJSONObject: [
            "action": "start",
            "template_id": templateId
        ])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(FieldTripStartResponse.self, from: data).data
    }

    func stopFieldTrip(userFieldTripId: String) async throws -> FieldTripTemplate {
        try await updateFieldTripLifecycle(
            action: "stop",
            userFieldTripId: userFieldTripId
        )
    }

    func resetFieldTrip(userFieldTripId: String) async throws -> FieldTripTemplate {
        try await updateFieldTripLifecycle(
            action: "reset",
            userFieldTripId: userFieldTripId
        )
    }

    private func updateFieldTripLifecycle(
        action: String,
        userFieldTripId: String
    ) async throws -> FieldTripTemplate {
        let functionUrl = try endpointURL("field-trips")
        let bodyData = try JSONSerialization.data(withJSONObject: [
            "action": action,
            "user_field_trip_id": userFieldTripId
        ])
        let (data, _) = try await performAuthenticatedRequest(
            url: functionUrl,
            method: "POST",
            body: bodyData
        )
        return try makeExploreDecoder().decode(
            FieldTripTemplateDetailResponse.self,
            from: data
        ).data
    }

    func getFieldTripChallenges(userRegion: String? = nil, limit: Int = 20) async throws -> [FieldTripChallenge] {
        let functionUrl = try endpointURL("field-trips")
        var payload: [String: Any] = [
            "action": "challenges_catalog",
            "limit": limit
        ]
        if let userRegion = userRegion?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            payload["user_region"] = userRegion
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(FieldTripChallengesCatalogResponse.self, from: data).data
    }

    func getFieldTripChallenge(challengeId: String, entriesLimit: Int = 12) async throws -> FieldTripChallenge {
        let functionUrl = try endpointURL("field-trips")
        let bodyData = try JSONSerialization.data(withJSONObject: [
            "action": "challenge_detail",
            "challenge_id": challengeId,
            "entries_limit": entriesLimit
        ])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(FieldTripChallengeDetailResponse.self, from: data).data
    }

    func joinFieldTripChallenge(challengeId: String) async throws -> FieldTripChallenge {
        let functionUrl = try endpointURL("field-trips")
        let bodyData = try JSONSerialization.data(withJSONObject: [
            "action": "join_challenge",
            "challenge_id": challengeId
        ])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(FieldTripChallengeDetailResponse.self, from: data).data
    }

    func getRecentFieldTripPublications(
        userRegion: String? = nil,
        habitatTags: [String] = [],
        limit: Int = 20,
        beforePublishedAt: String? = nil,
        beforePublicationId: String? = nil
    ) async throws -> [FieldTripRecentPublication] {
        try await getFieldTripCommunityPublications(
            mode: .recent,
            userRegion: userRegion,
            habitatTags: habitatTags,
            limit: limit,
            beforeRankBucket: beforePublishedAt == nil ? nil : 0,
            beforePublishedAt: beforePublishedAt,
            beforePublicationId: beforePublicationId
        )
    }

    func getFieldTripCommunityPublications(
        mode: FieldTripCommunityMode = .smart,
        templateId: String? = nil,
        userRegion: String? = nil,
        habitatTags: [String] = [],
        seasonTags: [String] = [],
        limit: Int = 20,
        beforeRankBucket: Int? = nil,
        beforePublishedAt: String? = nil,
        beforePublicationId: String? = nil
    ) async throws -> [FieldTripRecentPublication] {
        let functionUrl = try endpointURL("field-trips")
        var payload: [String: Any] = [
            "action": "community_publications",
            "mode": mode.rawValue,
            "limit": limit
        ]
        if let templateId = templateId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            payload["template_id"] = templateId
        }
        if let userRegion = userRegion?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            payload["user_region"] = userRegion
        }
        let trimmedHabitatTags = habitatTags.compactMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        if !trimmedHabitatTags.isEmpty {
            payload["habitat_tags"] = trimmedHabitatTags
        }
        let trimmedSeasonTags = seasonTags.compactMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        if !trimmedSeasonTags.isEmpty {
            payload["season_tags"] = trimmedSeasonTags
        }
        if let beforeRankBucket, let beforePublishedAt, let beforePublicationId {
            payload["before_rank_bucket"] = beforeRankBucket
            payload["before_published_at"] = beforePublishedAt
            payload["before_publication_id"] = beforePublicationId
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(FieldTripCommunityPublicationsResponse.self, from: data).data
    }

    func applyFieldTripProgress(
        scanId: String,
        preferredGoal: FieldTripPreferredGoal? = nil
    ) async throws -> FieldTripProgressResult {
        let functionUrl = try endpointURL("field-trips")
        var payload: [String: Any] = [
            "action": "apply_scan_progress",
            "scan_id": scanId
        ]
        if let preferredGoal {
            payload["preferred_goal"] = [
                "user_field_trip_id": preferredGoal.userFieldTripId,
                "item_id": preferredGoal.itemId
            ]
        }
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData, timeoutInterval: 15.0)
        let response = try makeExploreDecoder().decode(FieldTripProgressUpdatesResponse.self, from: data)
        return FieldTripProgressResult(
            fieldTripUpdates: response.data,
            challengeUpdates: response.challengeUpdates,
            firstFieldTripAchievement: response.firstFieldTripAchievement,
            firstFieldTripAchievementNewlyUnlocked:
                response.firstFieldTripAchievementNewlyUnlocked
        )
    }

    func getFieldTripScanContributions(scanId: String) async throws -> [FieldTripScanContribution] {
        let functionUrl = try endpointURL("field-trips")
        let bodyData = try JSONSerialization.data(withJSONObject: [
            "action": "scan_contributions",
            "scan_id": scanId
        ])
        let (data, _) = try await performAuthenticatedRequest(
            url: functionUrl,
            method: "POST",
            body: bodyData,
            timeoutInterval: 15.0
        )
        return try makeExploreDecoder()
            .decode(FieldTripScanContributionsResponse.self, from: data)
            .data
    }

    func getFieldTripChallengeHashtags(scanId: String) async throws -> [String] {
        let functionUrl = try endpointURL("field-trips")
        let bodyData = try JSONSerialization.data(withJSONObject: [
            "action": "scan_challenge_hashtags",
            "scan_id": scanId
        ])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(FieldTripChallengeHashtagsResponse.self, from: data).data
    }

    func getFieldTripProfileSummaries(authorUserId: String, limit: Int = 6) async throws -> FieldTripProfileSummaries {
        let functionUrl = try endpointURL("field-trips")
        let bodyData = try JSONSerialization.data(withJSONObject: [
            "action": "profile_summaries",
            "author_user_id": authorUserId,
            "limit": limit
        ])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(FieldTripProfileSummariesResponse.self, from: data).data
    }

    func setPinnedFieldTripPublications(publicationIds: [String]) async throws -> FieldTripProfileSummaries {
        let functionUrl = try endpointURL("field-trips")
        let bodyData = try JSONSerialization.data(withJSONObject: [
            "action": "set_pinned_publications",
            "publication_ids": Array(publicationIds.prefix(3))
        ])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(FieldTripSetPinnedPublicationsResponse.self, from: data).data
    }

    func publishFieldTrip(
        userFieldTripId: String,
        title: String? = nil,
        description: String? = nil,
        aiSummary: String? = nil
    ) async throws -> FieldTripPublicationDetail {
        let functionUrl = try endpointURL("field-trips")
        var payload: [String: Any] = [
            "action": "publish",
            "user_field_trip_id": userFieldTripId
        ]
        payload["title"] = title ?? NSNull()
        payload["description"] = description ?? NSNull()
        payload["ai_summary"] = aiSummary ?? NSNull()

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(FieldTripPublicationDetailResponse.self, from: data).data
    }

    func getFieldTripChallengePublications(
        challengeId: String,
        limit: Int = 20,
        beforePublishedAt: String? = nil,
        beforeEntryId: String? = nil
    ) async throws -> [FieldTripChallengeEntry] {
        let functionUrl = try endpointURL("field-trips")
        var payload: [String: Any] = [
            "action": "challenge_publications",
            "challenge_id": challengeId,
            "limit": limit
        ]
        if let beforePublishedAt, let beforeEntryId {
            payload["before_published_at"] = beforePublishedAt
            payload["before_entry_id"] = beforeEntryId
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(FieldTripChallengePublicationsResponse.self, from: data).data
    }

    func publishFieldTripChallengeEntry(
        participationId: String,
        title: String? = nil,
        description: String? = nil
    ) async throws -> FieldTripChallengeEntryDetail {
        let functionUrl = try endpointURL("field-trips")
        var payload: [String: Any] = [
            "action": "publish_challenge_entry",
            "participation_id": participationId
        ]
        payload["title"] = title ?? NSNull()
        payload["description"] = description ?? NSNull()

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(FieldTripChallengeEntryDetailResponse.self, from: data).data
    }

    func getFieldTripChallengeEntry(entryId: String) async throws -> FieldTripChallengeEntryDetail {
        let functionUrl = try endpointURL("field-trips")
        let bodyData = try JSONSerialization.data(withJSONObject: [
            "action": "challenge_entry_detail",
            "entry_id": entryId
        ])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(FieldTripChallengeEntryDetailResponse.self, from: data).data
    }

    func getFieldTripPublication(publicationId: String) async throws -> FieldTripPublicationDetail {
        let functionUrl = try endpointURL("field-trips")
        let bodyData = try JSONSerialization.data(withJSONObject: [
            "action": "detail",
            "publication_id": publicationId
        ])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(FieldTripPublicationDetailResponse.self, from: data).data
    }

    func setFieldTripLike(publicationId: String, liked: Bool) async throws -> FieldTripLikeResponse {
        let functionUrl = try endpointURL("field-trips")
        let bodyData = try JSONSerialization.data(withJSONObject: [
            "action": "set_like",
            "publication_id": publicationId,
            "liked": liked
        ])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(FieldTripLikeResponse.self, from: data)
    }

    func setFieldTripChallengeEntryLike(entryId: String, liked: Bool) async throws -> FieldTripChallengeEntryLikeResponse {
        let functionUrl = try endpointURL("field-trips")
        let bodyData = try JSONSerialization.data(withJSONObject: [
            "action": "set_challenge_entry_like",
            "entry_id": entryId,
            "liked": liked
        ])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(FieldTripChallengeEntryLikeResponse.self, from: data)
    }

    func getFieldTripComments(
        publicationId: String,
        limit: Int = 100,
        afterCreatedAt: String? = nil,
        afterCommentId: String? = nil
    ) async throws -> [ExploreComment] {
        let functionUrl = try endpointURL("field-trips")
        var payload: [String: Any] = [
            "action": "comments",
            "publication_id": publicationId,
            "limit": limit
        ]

        if let afterCreatedAt, let afterCommentId {
            payload["after_created_at"] = afterCreatedAt
            payload["after_comment_id"] = afterCommentId
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(FieldTripCommentsResponse.self, from: data).data
    }

    func getFieldTripChallengeEntryComments(
        entryId: String,
        limit: Int = 100,
        afterCreatedAt: String? = nil,
        afterCommentId: String? = nil
    ) async throws -> [ExploreComment] {
        let functionUrl = try endpointURL("field-trips")
        var payload: [String: Any] = [
            "action": "challenge_entry_comments",
            "entry_id": entryId,
            "limit": limit
        ]

        if let afterCreatedAt, let afterCommentId {
            payload["after_created_at"] = afterCreatedAt
            payload["after_comment_id"] = afterCommentId
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(FieldTripCommentsResponse.self, from: data).data
    }

    func createFieldTripComment(
        publicationId: String,
        body: String,
        parentCommentId: String? = nil
    ) async throws -> FieldTripCreateCommentResponse {
        let functionUrl = try endpointURL("field-trips")
        var payload: [String: Any] = [
            "action": "create_comment",
            "publication_id": publicationId,
            "body": body
        ]
        if let parentCommentId {
            payload["parent_comment_id"] = parentCommentId
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(FieldTripCreateCommentResponse.self, from: data)
    }

    func createFieldTripChallengeEntryComment(
        entryId: String,
        body: String,
        parentCommentId: String? = nil
    ) async throws -> FieldTripCreateCommentResponse {
        let functionUrl = try endpointURL("field-trips")
        var payload: [String: Any] = [
            "action": "create_challenge_entry_comment",
            "entry_id": entryId,
            "body": body
        ]
        if let parentCommentId {
            payload["parent_comment_id"] = parentCommentId
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(FieldTripCreateCommentResponse.self, from: data)
    }

    func getExploreHashtagPosts(
        hashtag: String,
        limit: Int = 30,
        cursor: ExploreHashtagPostCursor? = nil
    ) async throws -> [ExplorePost] {
        let functionUrl = try endpointURL("get-explore-hashtag-posts")
        var payload: [String: Any] = [
            "hashtag": hashtag,
            "limit": limit
        ]

        if let cursor,
           let beforeSharedAt = cursor.beforeSharedAt,
           let beforePostId = cursor.beforePostId {
            payload["before_shared_at"] = beforeSharedAt
            payload["before_post_id"] = beforePostId
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreHashtagPostsResponse.self, from: data).data
    }

    func getExploreSpeciesPosts(
        speciesId: String,
        limit: Int = 30,
        cursor: ExploreSpeciesPostCursor? = nil
    ) async throws -> ExploreSpeciesPostsResponse {
        let functionUrl = try endpointURL("get-explore-species-posts")
        var payload: [String: Any] = [
            "species_id": speciesId,
            "limit": limit
        ]

        if let cursor {
            if let imageQualityScore = cursor.imageQualityScore {
                payload["before_image_quality_score"] = imageQualityScore
            }
            payload["before_shared_at"] = cursor.sharedAt
            payload["before_post_id"] = cursor.postId
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreSpeciesPostsResponse.self, from: data)
    }

    func getExploreShareState(scanId: String) async throws -> ExploreScanShareState {
        let functionUrl = try endpointURL("get-scan-explore-share-state")
        let bodyData = try JSONSerialization.data(withJSONObject: ["scan_id": scanId])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        let state: ExploreScanShareState
        do {
            state = try makeExploreDecoder().decode(
                ExploreScanShareStateResponse.self,
                from: data
            ).data
        } catch {
            throw MerianError.invalidResponse
        }
        let postId = state.postId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let communityRequestId = state.communityRequestId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sharedAt = state.sharedAt.flatMap { value in
            DateUtilities.iso8601FractionalFormatter.date(from: value) ??
                DateUtilities.iso8601Formatter.date(from: value)
        }
        let hasPost = postId.flatMap { UUID(uuidString: $0) } != nil
        let hasCommunityRequest =
            communityRequestId.flatMap { UUID(uuidString: $0) } != nil
        let hasCommunityStatus = state.communityRequestStatus != nil

        // A valid post can be server-hidden without a Community request when
        // media is quarantined or the post is moderated. Visibility remains an
        // authoritative required field; only a visible-without-post claim is
        // structurally impossible.
        guard state.scanId.caseInsensitiveCompare(scanId) == .orderedSame,
              state.locationSharing != nil,
              hasPost == (state.postId != nil),
              hasPost == (state.sharedAt != nil),
              !hasPost || sharedAt != nil,
              hasCommunityRequest == (state.communityRequestId != nil),
              hasCommunityRequest == hasCommunityStatus,
              !hasCommunityRequest || hasPost,
              !state.isExploreFeedVisible || hasPost,
              !state.isExploreFeedVisible ||
                state.communityRequestStatus != .needsId,
              hasPost || (
                !state.isExploreFeedVisible &&
                !hasCommunityRequest
              ) else {
            throw MerianError.invalidResponse
        }
        return state
    }

    func getExploreNotifications(
        limit: Int = 50,
        beforeUpdatedAt: String? = nil,
        beforeNotificationId: String? = nil
    ) async throws -> [ExploreNotification] {
        let functionUrl = try endpointURL("get-explore-notifications")
        var payload: [String: Any] = ["limit": limit]

        if let beforeUpdatedAt, let beforeNotificationId {
            payload["before_updated_at"] = beforeUpdatedAt
            payload["before_notification_id"] = beforeNotificationId
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreNotificationsResponse.self, from: data).data
    }

    func getExploreMediaIncidents() async throws -> [ExploreMediaIncident] {
        let functionUrl = try endpointURL("get-explore-media-incidents")
        let (data, _) = try await performAuthenticatedRequest(
            url: functionUrl,
            method: "POST",
            body: Data("{}".utf8)
        )
        do {
            return try makeExploreDecoder().decode(
                ExploreMediaIncidentsResponse.self,
                from: data
            ).data
        } catch {
            throw MerianError.invalidResponse
        }
    }

    func getUnreadExploreNotificationCount() async throws -> Int {
        let functionUrl = try endpointURL("get-explore-unread-notification-count")
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: Data("{}".utf8))
        return try makeExploreDecoder().decode(ExploreUnreadNotificationCountResponse.self, from: data).unreadCount
    }

    func markExploreNotificationsRead() async throws -> Int {
        let functionUrl = try endpointURL("mark-explore-notifications-read")
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: Data("{}".utf8))
        return try makeExploreDecoder().decode(ExploreMarkNotificationsReadResponse.self, from: data).markedCount
    }

    func updatePublicUsername(_ username: String) async throws -> PublicUsernameUpdateResponse {
        let functionUrl = try endpointURL("update-public-username")
        let bodyData = try JSONSerialization.data(withJSONObject: [
            "username": username
        ])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(PublicUsernameUpdateResponse.self, from: data)
    }

    func updatePublicDisplayName(_ displayName: String) async throws -> PublicDisplayNameUpdateResponse {
        let functionUrl = try endpointURL("update-public-display-name")
        let bodyData = try JSONSerialization.data(withJSONObject: [
            "display_name": displayName
        ])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(PublicDisplayNameUpdateResponse.self, from: data)
    }

    func updatePublicAvatar(r2ObjectKey: String, mimeType: String) async throws -> PublicAvatarUpdateResponse {
        let functionUrl = try endpointURL("update-public-avatar")
        let bodyData = try JSONSerialization.data(withJSONObject: [
            "r2_object_key": r2ObjectKey,
            "mime_type": mimeType
        ])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(PublicAvatarUpdateResponse.self, from: data)
    }

    func checkPublicUsernameAvailability(_ username: String) async throws -> PublicUsernameAvailabilityResponse {
        let functionUrl = try endpointURL("check-public-username")
        let bodyData = try JSONSerialization.data(withJSONObject: [
            "username": username
        ])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(PublicUsernameAvailabilityResponse.self, from: data)
    }

    func registerPushDevice(
        deviceToken: String,
        environment: String,
        exploreEnabled: Bool,
        commentMentionsEnabled: Bool,
        communityIdentificationsEnabled: Bool
    ) async throws {
        let functionUrl = try endpointURL("register-push-device")
        let payload: [String: Any] = [
            "device_token": deviceToken,
            "platform": "ios",
            "environment": environment,
            "explore_enabled": exploreEnabled,
            "comment_mentions_enabled": commentMentionsEnabled,
            "community_identifications_enabled": communityIdentificationsEnabled
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
    }

    func shareScanToExplore(
        scanId: String,
        restoredObjectKeys: [String]? = nil,
        restoredVideoObjectKeys: [String]? = nil,
        restoredAudioObjectKeys: [String]? = nil,
        speciesCommonName: String? = nil,
        fieldNotes: String? = nil,
        hashtags: [String] = [],
        locationSharing: ExplorePostLocationSharing? = nil,
        mediaItems: [ExplorePostMediaSelection]? = nil,
        idempotencyKey: String? = nil,
        recoveryScan: OwnedScanRecoveryPayload? = nil
    ) async throws -> ExploreShareResponse {
        let functionUrl = try endpointURL("share-scan-to-explore")
        let resolvedIdempotencyKey = idempotencyKey ?? UUID().uuidString.lowercased()
        var payload: [String: Any] = [
            "scan_id": scanId,
            "field_notes": fieldNotes ?? NSNull(),
            "hashtags": hashtags
        ]
        if let mediaItems {
            payload["media_items"] = mediaItems.map(\.jsonObject)
        }
        if let locationSharing {
            payload["location_sharing"] = locationSharing.rawValue
        }
        let trimmedCommonName = speciesCommonName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedCommonName, !trimmedCommonName.isEmpty {
            payload["species_common_name"] = trimmedCommonName
        }
        if let restoredObjectKeys, !restoredObjectKeys.isEmpty {
            payload["restored_object_keys"] = restoredObjectKeys
        }
        if let restoredVideoObjectKeys, !restoredVideoObjectKeys.isEmpty {
            payload["restored_video_object_keys"] = restoredVideoObjectKeys
        }
        if let restoredAudioObjectKeys, !restoredAudioObjectKeys.isEmpty {
            payload["restored_audio_object_keys"] = restoredAudioObjectKeys
        }
        if let recoveryScan {
            let recoveryData = try JSONEncoder().encode(recoveryScan)
            guard let recoveryObject = try JSONSerialization.jsonObject(with: recoveryData) as? [String: Any] else {
                throw MerianError.invalidResponse
            }
            payload["recovery_scan"] = recoveryObject
        }
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(
            url: functionUrl,
            method: "POST",
            body: bodyData,
            idempotencyKey: resolvedIdempotencyKey
        )
        let decoded: ExploreShareResponse
        do {
            decoded = try makeExploreDecoder().decode(
                ExploreShareResponse.self,
                from: data
            )
        } catch {
            throw MerianError.invalidResponse
        }
        guard decoded.success,
              decoded.scanId.caseInsensitiveCompare(scanId) == .orderedSame,
              UUID(uuidString: decoded.postId) != nil,
              (
                DateUtilities.iso8601FractionalFormatter.date(
                    from: decoded.sharedAt
                ) ??
                DateUtilities.iso8601Formatter.date(from: decoded.sharedAt)
              ) != nil,
              decoded.locationSharing != nil,
              locationSharing == nil ||
                decoded.locationSharing == locationSharing,
              decoded.publicationStatus == "published" else {
            throw MerianError.invalidResponse
        }
        return decoded
    }

    func shareScanToExplore(
        scan: LocalScanRecord,
        fallbackImageData: Data? = nil,
        speciesCommonName: String? = nil,
        fieldNotes: String? = nil,
        hashtags: [String] = [],
        locationSharing: ExplorePostLocationSharing? = nil,
        mediaItems: [ExplorePostMediaSelection]? = nil
    ) async throws -> ExploreShareResponse {
        let mediaSnapshot = ExploreShareMediaSnapshot(scan: scan, fallbackImageData: fallbackImageData)
        let idempotencyKey = UUID().uuidString.lowercased()
        do {
            return try await shareScanToExplore(
                scanId: mediaSnapshot.scanId,
                speciesCommonName: speciesCommonName,
                fieldNotes: fieldNotes,
                hashtags: hashtags,
                locationSharing: locationSharing,
                mediaItems: mediaItems,
                idempotencyKey: idempotencyKey
            )
        } catch {
            if Self.shouldAttemptExploreCloudScanRestore(after: error) {
                MerianLog.network.debug("Explore share missing cloud scan; attempting local scan recovery for \(mediaSnapshot.scanId, privacy: .private).")
                switch await waitForScanPersistence(scanId: mediaSnapshot.scanId) {
                case .found:
                    MerianLog.network.debug("Explore scan persistence completed; retrying share for \(mediaSnapshot.scanId, privacy: .private).")
                    return try await shareScanToExplore(
                        scanId: mediaSnapshot.scanId,
                        speciesCommonName: speciesCommonName,
                        fieldNotes: fieldNotes,
                        hashtags: hashtags,
                        locationSharing: locationSharing,
                        mediaItems: mediaItems,
                        idempotencyKey: idempotencyKey
                    )
                case .deferRecovery:
                    throw error
                case .serviceUnavailable:
                    throw MerianError.edgeFunctionUnavailable
                case .recoverableMissing:
                    break
                }

                let recoveryScan = try await makeOwnedScanRecoveryPayload(
                    for: mediaSnapshot,
                    locationSharing: locationSharing
                )
                let recovered = try await recoverMissingOwnedCloudScan(
                    for: mediaSnapshot,
                    locationSharing: locationSharing,
                    recoveryScan: recoveryScan
                )
                guard recovered else {
                    throw error
                }
                let restoredObjectKeys = try await restoreExploreMediaObjectKeys(
                    for: mediaSnapshot,
                    includeAudio: true
                )
                guard !restoredObjectKeys.isEmpty else {
                    MerianLog.network.debug("Explore share cloud scan recovery could not find restorable local media for \(mediaSnapshot.scanId, privacy: .private).")
                    throw error
                }

                MerianLog.network.debug("Explore share cloud scan recovery uploaded \(restoredObjectKeys.imageObjectKeys.count + restoredObjectKeys.videoObjectKeys.count + restoredObjectKeys.audioObjectKeys.count, privacy: .public) media item(s); retrying.")
                return try await shareScanToExplore(
                    scanId: mediaSnapshot.scanId,
                    restoredObjectKeys: restoredObjectKeys.imageObjectKeys,
                    restoredVideoObjectKeys: restoredObjectKeys.videoObjectKeys,
                    restoredAudioObjectKeys: restoredObjectKeys.audioObjectKeys,
                    speciesCommonName: speciesCommonName,
                    fieldNotes: fieldNotes,
                    hashtags: hashtags,
                    locationSharing: locationSharing,
                    mediaItems: mediaItems,
                    idempotencyKey: idempotencyKey,
                    recoveryScan: recoveryScan
                )
            }

            guard shouldAttemptExploreMediaRestore(after: error) else {
                throw error
            }

            let restoredObjectKeys = try await restoreExploreMediaObjectKeys(
                for: mediaSnapshot,
                includeImages: shouldRestoreExploreImages(after: error),
                includeAudio: true
            )
            guard !restoredObjectKeys.isEmpty else {
                throw error
            }

            return try await shareScanToExplore(
                scanId: mediaSnapshot.scanId,
                restoredObjectKeys: restoredObjectKeys.imageObjectKeys,
                restoredVideoObjectKeys: restoredObjectKeys.videoObjectKeys,
                restoredAudioObjectKeys: restoredObjectKeys.audioObjectKeys,
                speciesCommonName: speciesCommonName,
                fieldNotes: fieldNotes,
                hashtags: hashtags,
                locationSharing: locationSharing,
                mediaItems: mediaItems,
                idempotencyKey: idempotencyKey
            )
        }
    }

    func requestCommunityIdentification(
        scanId: String,
        restoredObjectKeys: [String]? = nil,
        restoredVideoObjectKeys: [String]? = nil,
        restoredAudioObjectKeys: [String]? = nil,
        speciesCommonName: String? = nil,
        note: String? = nil,
        locationSharing: ExplorePostLocationSharing? = nil,
        idempotencyKey: String? = nil
    ) async throws -> CommunityIdentificationRequest {
        let functionUrl = try endpointURL("request-community-identification")
        let resolvedIdempotencyKey = idempotencyKey ?? UUID().uuidString.lowercased()
        var payload: [String: Any] = [
            "scan_id": scanId,
            "note": note ?? NSNull()
        ]
        if let locationSharing {
            payload["location_sharing"] = locationSharing.rawValue
        }
        let trimmedCommonName = speciesCommonName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedCommonName, !trimmedCommonName.isEmpty {
            payload["species_common_name"] = trimmedCommonName
        }
        if let restoredObjectKeys, !restoredObjectKeys.isEmpty {
            payload["restored_object_keys"] = restoredObjectKeys
        }
        if let restoredVideoObjectKeys, !restoredVideoObjectKeys.isEmpty {
            payload["restored_video_object_keys"] =
                restoredVideoObjectKeys
        }
        if let restoredAudioObjectKeys, !restoredAudioObjectKeys.isEmpty {
            payload["restored_audio_object_keys"] =
                restoredAudioObjectKeys
        }
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(
            url: functionUrl,
            method: "POST",
            body: bodyData,
            idempotencyKey: resolvedIdempotencyKey
        )
        let decoded: CommunityIdentificationRequestResponse
        do {
            decoded = try makeExploreDecoder().decode(
                CommunityIdentificationRequestResponse.self,
                from: data
            )
        } catch {
            throw MerianError.invalidResponse
        }
        let request = decoded.data
        guard decoded.success,
              request.scanId.caseInsensitiveCompare(scanId) == .orderedSame,
              UUID(uuidString: request.id) != nil,
              UUID(uuidString: request.postId) != nil,
              UUID(uuidString: request.requestedBy) != nil,
              request.initialTaxonNodeId.flatMap({
                  UUID(uuidString: $0)
              }) != nil,
              request.taxonomyVersionId.flatMap({
                  UUID(uuidString: $0)
              }) != nil,
              (
                DateUtilities.iso8601FractionalFormatter.date(
                    from: request.requestedAt
                ) ??
                DateUtilities.iso8601Formatter.date(from: request.requestedAt)
              ) != nil,
              request.status == .needsId,
              request.consensusIdentificationCount >= 0 else {
            throw MerianError.invalidResponse
        }
        return request
    }

    func requestCommunityIdentification(
        scan: LocalScanRecord,
        fallbackImageData: Data? = nil,
        speciesCommonName: String? = nil,
        note: String? = nil,
        locationSharing: ExplorePostLocationSharing? = nil
    ) async throws -> CommunityIdentificationRequest {
        let mediaSnapshot = ExploreShareMediaSnapshot(scan: scan, fallbackImageData: fallbackImageData)
        let idempotencyKey = UUID().uuidString.lowercased()
        do {
            return try await requestCommunityIdentification(
                scanId: mediaSnapshot.scanId,
                speciesCommonName: speciesCommonName,
                note: note,
                locationSharing: locationSharing,
                idempotencyKey: idempotencyKey
            )
        } catch {
            if Self.shouldAttemptExploreCloudScanRestore(after: error) {
                MerianLog.network.debug("Community request missing cloud scan; attempting local scan recovery for \(mediaSnapshot.scanId, privacy: .private).")
                switch await waitForScanPersistence(scanId: mediaSnapshot.scanId) {
                case .found:
                    return try await requestCommunityIdentification(
                        scanId: mediaSnapshot.scanId,
                        speciesCommonName: speciesCommonName,
                        note: note,
                        locationSharing: locationSharing,
                        idempotencyKey: idempotencyKey
                    )
                case .deferRecovery:
                    throw error
                case .serviceUnavailable:
                    throw MerianError.edgeFunctionUnavailable
                case .recoverableMissing:
                    break
                }

                let recovered = try await recoverMissingOwnedCloudScan(
                    for: mediaSnapshot,
                    locationSharing: locationSharing
                )
                guard recovered else {
                    throw error
                }
                let restoredObjectKeys = try await restoreExploreMediaObjectKeys(
                    for: mediaSnapshot,
                    includeAudio: true
                )
                guard !restoredObjectKeys.isEmpty else {
                    MerianLog.network.debug("Community request cloud scan recovery could not find restorable local media for \(mediaSnapshot.scanId, privacy: .private).")
                    throw error
                }

                MerianLog.network.debug("Community request cloud scan recovery uploaded \(restoredObjectKeys.imageObjectKeys.count + restoredObjectKeys.videoObjectKeys.count + restoredObjectKeys.audioObjectKeys.count, privacy: .public) media item(s); retrying.")
                return try await requestCommunityIdentification(
                    scanId: mediaSnapshot.scanId,
                    restoredObjectKeys: restoredObjectKeys.imageObjectKeys,
                    restoredVideoObjectKeys:
                        restoredObjectKeys.videoObjectKeys,
                    restoredAudioObjectKeys:
                        restoredObjectKeys.audioObjectKeys,
                    speciesCommonName: speciesCommonName,
                    note: note,
                    locationSharing: locationSharing,
                    idempotencyKey: idempotencyKey
                )
            }

            guard shouldAttemptExploreMediaRestore(after: error) else {
                throw error
            }

            let restoredObjectKeys = try await restoreExploreMediaObjectKeys(
                for: mediaSnapshot,
                includeAudio: true
            )
            guard !restoredObjectKeys.isEmpty else {
                throw error
            }

            return try await requestCommunityIdentification(
                scanId: mediaSnapshot.scanId,
                restoredObjectKeys: restoredObjectKeys.imageObjectKeys,
                restoredVideoObjectKeys:
                    restoredObjectKeys.videoObjectKeys,
                restoredAudioObjectKeys:
                    restoredObjectKeys.audioObjectKeys,
                speciesCommonName: speciesCommonName,
                note: note,
                locationSharing: locationSharing,
                idempotencyKey: idempotencyKey
            )
        }
    }

    func unshareExplorePost(postId: String) async throws {
        let functionUrl = try endpointURL("unshare-explore-post")
        let bodyData = try JSONSerialization.data(withJSONObject: ["post_id": postId])
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
    }

    func updateExplorePostFieldNotes(postId: String, fieldNotes: String?) async throws -> ExploreUpdateFieldNotesResponse {
        let functionUrl = try endpointURL("update-explore-field-notes")
        let payload: [String: Any] = [
            "post_id": postId,
            "field_notes": fieldNotes ?? NSNull()
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreUpdateFieldNotesResponse.self, from: data)
    }

    func updateExplorePostContent(
        postId: String,
        speciesCommonName: String? = nil,
        fieldNotes: String?,
        hashtags: [String],
        locationSharing: ExplorePostLocationSharing,
        mediaItems: [ExplorePostMediaSelection]? = nil
    ) async throws -> ExploreUpdateFieldNotesResponse {
        let functionUrl = try endpointURL("update-explore-field-notes")
        var payload: [String: Any] = [
            "post_id": postId,
            "field_notes": fieldNotes ?? NSNull(),
            "hashtags": hashtags,
            "location_sharing": locationSharing.rawValue
        ]
        if let mediaItems {
            payload["media_items"] = mediaItems.map(\.jsonObject)
        }
        let trimmedCommonName = speciesCommonName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedCommonName, !trimmedCommonName.isEmpty {
            payload["species_common_name"] = trimmedCommonName
        }
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(
            url: functionUrl,
            method: "POST",
            body: bodyData,
            idempotencyKey: UUID().uuidString.lowercased()
        )
        return try makeExploreDecoder().decode(ExploreUpdateFieldNotesResponse.self, from: data)
    }

    func setExplorePostLike(postId: String, liked: Bool) async throws -> ExploreLikeResponse {
        let functionUrl = try endpointURL("set-explore-post-like")
        let payload: [String: Any] = [
            "post_id": postId,
            "liked": liked
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreLikeResponse.self, from: data)
    }

    func setUserFollow(authorUserId: String, isFollowing: Bool) async throws -> ExploreFollowState {
        let functionUrl = try endpointURL("set-user-follow")
        let payload: [String: Any] = [
            "author_user_id": authorUserId,
            "is_following": isFollowing
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreFollowState.self, from: data)
    }

    func createExploreComment(postId: String, body: String, parentCommentId: String? = nil) async throws -> ExploreCreateCommentResponse {
        let functionUrl = try endpointURL("create-explore-comment")
        var payload: [String: Any] = [
            "post_id": postId,
            "body": body
        ]
        if let parentCommentId {
            payload["parent_comment_id"] = parentCommentId
        }
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreCreateCommentResponse.self, from: data)
    }

    func deleteExploreComment(commentId: String) async throws -> ExploreDeleteCommentResponse {
        let functionUrl = try endpointURL("delete-explore-comment")
        let bodyData = try JSONSerialization.data(withJSONObject: ["comment_id": commentId])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreDeleteCommentResponse.self, from: data)
    }

    func toggleExploreCommentReaction(commentId: String, emoji: String) async throws {
        let functionUrl = try endpointURL("toggle-explore-comment-reaction")
        let payload: [String: Any] = [
            "comment_id": commentId,
            "emoji": emoji
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
    }

    func reportExploreComment(
        commentId: String,
        reason: String = "Inappropriate content",
        details: String = "Reported from Explore comments"
    ) async throws {
        let functionUrl = try endpointURL("report-explore-comment")
        let payload: [String: Any] = [
            "comment_id": commentId,
            "reason": reason,
            "details": details
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
    }

    func reportExplorePost(
        postId: String,
        reason: String = "Inappropriate content",
        details: String = "Reported from Explore feed"
    ) async throws {
        let functionUrl = try endpointURL("report-explore-post")
        let payload: [String: Any] = [
            "post_id": postId,
            "reason": reason,
            "details": details
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
    }

    func reportUser(
        reportedUserId: String,
        reason: ExploreUserReportReason,
        details: String?
    ) async throws {
        let functionUrl = try endpointURL("report-user")
        var payload: [String: Any] = [
            "reported_user_id": reportedUserId,
            "reason": reason.rawValue
        ]
        if let details = details?.trimmingCharacters(in: .whitespacesAndNewlines), !details.isEmpty {
            payload["details"] = details
        }
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
    }

    // MARK: - Product Feedback

    func submitFeedbackSurvey(_ submission: FeedbackSurveySubmission) async throws {
        let functionUrl = try endpointURL("submit-feedback-survey")
        let bodyData = try JSONEncoder().encode(submission)
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
    }

    func submitCommunityFeedback(feedback: String) async throws {
        let submission = CommunityFeedbackSubmission(feedback: feedback)
        let functionUrl = try endpointURL("submit-community-feedback")
        let bodyData = try JSONEncoder().encode(submission)
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
    }

    // MARK: - Moderation

    func submitFlagIssue(scanId: String, flagReason: String, userSuggestion: String, userId: String) async throws {
        let functionUrl = try endpointURL("flag-issue")
        let payload: [String: Any] = [
            "scanId": scanId,
            "userId": userId,
            "flagReason": flagReason,
            "userSuggestion": userSuggestion
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
    }

    func blockUser(targetUserId: String) async throws {
        let functionUrl = try endpointURL("block-user")
        let bodyData = try JSONSerialization.data(withJSONObject: ["blocked_id": targetUserId])
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
    }

    // MARK: - Insight Chat

    func loadInsightChat(scanId: String) async throws -> InsightChatResponse {
        try await insightChat(
            action: "load",
            scanId: scanId,
            messageText: nil,
            clientMessageId: nil
        )
    }

    func sendInsightChatMessage(
        scanId: String,
        messageText: String,
        clientMessageId: String
    ) async throws -> InsightChatResponse {
        try await insightChat(
            action: "send",
            scanId: scanId,
            messageText: messageText,
            clientMessageId: clientMessageId
        )
    }

    func deleteInsightChat(scanId: String) async throws -> InsightChatResponse {
        try await insightChat(
            action: "delete",
            scanId: scanId,
            messageText: nil,
            clientMessageId: nil
        )
    }

    private func insightChat(
        action: String,
        scanId: String,
        messageText: String?,
        clientMessageId: String?
    ) async throws -> InsightChatResponse {
        let functionUrl = try endpointURL("insight-chat")
        let body = InsightChatRequestBody(
            action: action,
            scanId: scanId,
            messageText: messageText,
            clientMessageId: clientMessageId,
            messageId: nil,
            feedbackRating: nil,
            feedbackNote: nil,
            featureFeedbackSentiment: nil
        )
        let bodyData = try JSONEncoder().encode(body)
        let (data, _) = try await performAuthenticatedRequest(
            url: functionUrl,
            method: "POST",
            body: bodyData,
            timeoutInterval: 45.0,
            idempotencyKey: action == "send" ? clientMessageId : nil
        )
        return try decodeInsightChatResponse(
            data,
            expectedSubjectId: scanId,
            expectedClientMessageId:
                action == "send" ? clientMessageId : nil,
            expectedUserMessageText:
                action == "send" ? messageText : nil
        )
    }

    func submitInsightChatFeedback(
        scanId: String,
        messageId: String,
        rating: InsightChatFeedbackRating,
        note: String? = nil
    ) async throws -> InsightChatFeedbackResponse {
        let body = InsightChatRequestBody(
            action: "feedback",
            scanId: scanId,
            messageText: nil,
            clientMessageId: nil,
            messageId: messageId,
            feedbackRating: rating,
            feedbackNote: note,
            featureFeedbackSentiment: nil
        )
        let data = try await performInsightChatRequest(body)
        return try decodeInsightChatFeedbackResponse(
            data,
            expectedSubjectId: scanId,
            expectedMessageId: messageId,
            expectedRating: rating
        )
    }

    func submitInsightChatFeatureFeedback(
        scanId: String,
        sentiment: InsightChatFeatureFeedbackSentiment?,
        note: String?
    ) async throws -> InsightChatFeatureFeedbackResponse {
        let body = InsightChatRequestBody(
            action: "feature_feedback",
            scanId: scanId,
            messageText: nil,
            clientMessageId: nil,
            messageId: nil,
            feedbackRating: nil,
            feedbackNote: note,
            featureFeedbackSentiment: sentiment
        )
        let data = try await performInsightChatRequest(body)
        return try decodeInsightChatFeatureFeedbackResponse(
            data,
            expectedSubjectId: scanId,
            expectedSentiment: sentiment
        )
    }

    func summarizeInsightChatForFieldNotes(scanId: String) async throws -> InsightChatSummaryResponse {
        let body = InsightChatRequestBody(
            action: "summarize_notes",
            scanId: scanId,
            messageText: nil,
            clientMessageId: nil,
            messageId: nil,
            feedbackRating: nil,
            feedbackNote: nil,
            featureFeedbackSentiment: nil
        )
        let data = try await performInsightChatRequest(
            body,
            timeoutInterval: 45.0,
            idempotencyKey: UUID().uuidString.lowercased()
        )
        return try decodeInsightChatSummaryResponse(
            data,
            expectedSubjectId: scanId
        )
    }

    func suggestInsightChatPrompts(scanId: String) async throws -> InsightChatPromptSuggestionsResponse {
        let body = InsightChatRequestBody(
            action: "suggest_prompts",
            scanId: scanId,
            messageText: nil,
            clientMessageId: nil,
            messageId: nil,
            feedbackRating: nil,
            feedbackNote: nil,
            featureFeedbackSentiment: nil
        )
        let data = try await performInsightChatRequest(
            body,
            timeoutInterval: 30.0,
            idempotencyKey: UUID().uuidString.lowercased()
        )
        return try decodeInsightChatPromptSuggestionsResponse(
            data,
            expectedSubjectId: scanId
        )
    }

    private func performInsightChatRequest(
        _ body: InsightChatRequestBody,
        timeoutInterval: TimeInterval = 20.0,
        idempotencyKey: String? = nil
    ) async throws -> Data {
        let functionUrl = try endpointURL("insight-chat")
        let bodyData = try JSONEncoder().encode(body)
        let (data, _) = try await performAuthenticatedRequest(
            url: functionUrl,
            method: "POST",
            body: bodyData,
            timeoutInterval: timeoutInterval,
            idempotencyKey: idempotencyKey
        )
        return data
    }

    func loadExplorePostChat(postId: String) async throws -> InsightChatResponse {
        try await performExplorePostChat(
            action: "load",
            postId: postId
        )
    }

    func sendExplorePostChatMessage(
        postId: String,
        messageText: String,
        clientMessageId: String
    ) async throws -> InsightChatResponse {
        try await performExplorePostChat(
            action: "send",
            postId: postId,
            messageText: messageText,
            clientMessageId: clientMessageId
        )
    }

    func deleteExplorePostChat(postId: String) async throws -> InsightChatResponse {
        try await performExplorePostChat(action: "delete", postId: postId)
    }

    func submitExplorePostChatFeedback(
        postId: String,
        messageId: String,
        rating: InsightChatFeedbackRating,
        note: String? = nil
    ) async throws -> InsightChatFeedbackResponse {
        let body = ExplorePostChatRequestBody(
            action: "feedback",
            postId: postId,
            messageText: nil,
            clientMessageId: nil,
            messageId: messageId,
            feedbackRating: rating,
            feedbackNote: note
        )
        let data = try await performExplorePostChatRequest(body)
        return try decodeInsightChatFeedbackResponse(
            data,
            expectedSubjectId: postId,
            expectedMessageId: messageId,
            expectedRating: rating
        )
    }

    func suggestExplorePostChatPrompts(postId: String) async throws -> InsightChatPromptSuggestionsResponse {
        let body = ExplorePostChatRequestBody(
            action: "suggest_prompts",
            postId: postId,
            messageText: nil,
            clientMessageId: nil,
            messageId: nil,
            feedbackRating: nil,
            feedbackNote: nil
        )
        let data = try await performExplorePostChatRequest(body, timeoutInterval: 30.0)
        return try decodeInsightChatPromptSuggestionsResponse(
            data,
            expectedSubjectId: postId
        )
    }

    private func performExplorePostChat(
        action: String,
        postId: String,
        messageText: String? = nil,
        clientMessageId: String? = nil
    ) async throws -> InsightChatResponse {
        let body = ExplorePostChatRequestBody(
            action: action,
            postId: postId,
            messageText: messageText,
            clientMessageId: clientMessageId,
            messageId: nil,
            feedbackRating: nil,
            feedbackNote: nil
        )
        let data = try await performExplorePostChatRequest(
            body,
            idempotencyKey: action == "send" ? clientMessageId : nil
        )
        return try decodeInsightChatResponse(
            data,
            expectedSubjectId: postId,
            expectedClientMessageId:
                action == "send" ? clientMessageId : nil,
            expectedUserMessageText:
                action == "send" ? messageText : nil
        )
    }

    private func performExplorePostChatRequest(
        _ body: ExplorePostChatRequestBody,
        timeoutInterval: TimeInterval = 20.0,
        idempotencyKey: String? = nil
    ) async throws -> Data {
        let functionUrl = try endpointURL("explore-post-chat")
        let bodyData = try JSONEncoder().encode(body)
        let (data, _) = try await performAuthenticatedRequest(
            url: functionUrl,
            method: "POST",
            body: bodyData,
            timeoutInterval: timeoutInterval,
            idempotencyKey: idempotencyKey
        )
        return data
    }

    private func shouldAttemptExploreMediaRestore(after error: Error) -> Bool {
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

    private func shouldRestoreExploreImages(after error: Error) -> Bool {
        guard case let MerianError.httpError(statusCode, message) = error else {
            return true
        }

        return !(statusCode == 400 && (
            message.contains("Selected video media does not belong to this scan.")
                || message.contains("Selected audio media does not belong to this scan.")
        ))
    }

    static func shouldAttemptExploreCloudScanRestore(after error: Error) -> Bool {
        guard case let MerianError.httpError(statusCode, message) = error,
              statusCode == 404 else {
            return false
        }

        if let code = stableEdgeErrorCode(from: error) {
            return code == "not_found"
        }

        return message.localizedCaseInsensitiveContains("Scan not found")
    }

    @MainActor
    func ensureCloudScanAvailableForFieldChat(
        scan: LocalScanRecord,
        expectedScanId: String
    ) async throws -> Bool {
        let snapshot = ExploreShareMediaSnapshot(scan: scan)
        guard snapshot.scanId.caseInsensitiveCompare(expectedScanId) == .orderedSame else {
            throw MerianError.invalidResponse
        }
        switch await waitForScanPersistence(scanId: snapshot.scanId) {
        case .found:
            return true
        case .deferRecovery:
            return false
        case .serviceUnavailable:
            throw MerianError.edgeFunctionUnavailable
        case .recoverableMissing:
            return try await recoverMissingOwnedCloudScan(
                for: snapshot,
                locationSharing: nil
            )
        }
    }

    private func waitForScanPersistence(scanId: String) async -> ScanPersistenceProbeResult {
        let retryDelaysNanoseconds: [UInt64] = [
            0,
            250_000_000,
            500_000_000,
            1_000_000_000,
            2_000_000_000
        ]

        for delay in retryDelaysNanoseconds {
            if delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return .deferRecovery
                }
            }

            let status: ScanStatusResponse
            do {
                status = try await checkScanStatusDetails(scanId: scanId)
            } catch MerianError.edgeFunctionUnavailable {
                return .serviceUnavailable
            } catch {
                return .deferRecovery
            }
            if status.isFound {
                return .found
            }

            switch missingScanRecoveryAction(
                for: status.jobStatus,
                jobStage: status.jobStage,
                jobLastError: status.lastError
            ) {
            case .retryStatus:
                continue
            case .deferRecovery:
                return .deferRecovery
            case .recover:
                MerianLog.network.debug(
                    "Scan persistence unavailable for \(scanId, privacy: .private); job status=\(status.jobStatus?.rawValue ?? "none", privacy: .public) stage=\(status.jobStage ?? "none", privacy: .public)."
                )
                return .recoverableMissing
            }
        }

        return .deferRecovery
    }

    private func recoverMissingOwnedCloudScan(
        for scan: ExploreShareMediaSnapshot,
        locationSharing: ExplorePostLocationSharing?,
        recoveryScan: OwnedScanRecoveryPayload? = nil
    ) async throws -> Bool {
        let payload: OwnedScanRecoveryPayload
        if let recoveryScan {
            payload = recoveryScan
        } else {
            payload = try await makeOwnedScanRecoveryPayload(
                for: scan,
                locationSharing: locationSharing
            )
        }
        let status = try await checkScanStatusDetails(
            scanId: scan.scanId,
            recoveryScan: payload
        )
        return status.isFound
    }

    private func makeOwnedScanRecoveryPayload(
        for scan: ExploreShareMediaSnapshot,
        locationSharing: ExplorePostLocationSharing?
    ) async throws -> OwnedScanRecoveryPayload {
        let authUserId = try await SupabaseManager.shared.client.auth.session.user.id.uuidString.lowercased()
        let defaultGeoprivacy = await MainActor.run {
            AppDIContainer.shared.profileViewModel.defaultGeoprivacy
        }
        let geoprivacy = normalizedExploreScanGeoprivacy(locationSharing?.rawValue ?? defaultGeoprivacy)
        let serverSpeciesId = try await resolveExploreCloudSpeciesId(scientificName: scan.scientificName)
        let publicLocationLabel = geoprivacy == "private"
            ? nil
            : ExploreLocationPrivacy.displayLabel(from: scan.locationName)
        let exposesExactPublicCoordinates = geoprivacy == "open"

        return OwnedScanRecoveryPayload(
            id: scan.scanId,
            userId: authUserId,
            speciesId: serverSpeciesId,
            confirmedSpeciesId: scan.userConfirmedIdentification ? serverSpeciesId : nil,
            imageStorageUrls: [],
            timestamp: DateUtilities.iso8601Formatter.string(from: scan.captureDate ?? scan.timestamp),
            gpsLatExact: scan.gpsLatitude,
            gpsLongExact: scan.gpsLongitude,
            gpsLatPublic: exposesExactPublicCoordinates ? scan.gpsLatitude : nil,
            gpsLongPublic: exposesExactPublicCoordinates ? scan.gpsLongitude : nil,
            gpsElevation: scan.gpsElevation,
            geoprivacy: geoprivacy,
            weatherCondition: scan.weatherCondition?.nilIfEmpty,
            weatherTemperatureF: scan.weatherTemperatureF,
            aiConfidenceScore: normalizedExploreConfidence(scan.confidenceScore),
            ecologyType: normalizedExploreEcologyType(scan.ecologyType),
            isInvasive: scan.isInvasive,
            invasiveStatusRegion: scan.invasiveStatusRegion?.nilIfEmpty,
            invasiveRationale: scan.invasiveRationale?.nilIfEmpty,
            invasiveConfidence: scan.invasiveConfidence,
            isLiveCapture: scan.isLiveCapture,
            isBiologicalSubject: scan.isBiological,
            aiReasoning: scan.aiReasoning?.nilIfEmpty,
            semanticLocation: scan.locationName?.nilIfEmpty,
            publicLocationLabel: publicLocationLabel,
            inferenceTier: normalizedExploreInferenceTier(scan.inferenceTier),
            imageQualityScore: scan.imageQualityScore,
            userIdentificationOverride: scan.userIdentificationOverride?.nilIfEmpty,
            userConfirmedIdentification: scan.userConfirmedIdentification,
            userReviewState: normalizedExploreUserReviewState(
                rawValue: scan.userReviewStateRaw,
                userConfirmedIdentification: scan.userConfirmedIdentification,
                userIdentificationOverride: scan.userIdentificationOverride
            )
        )
    }

    private func resolveExploreCloudSpeciesId(scientificName: String) async throws -> String? {
        let trimmedScientificName = scientificName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedScientificName.isEmpty else { return nil }

        let rows: [ExploreCloudSpeciesIdRow] = try await SupabaseManager.shared.client
            .from("species_dictionary")
            .select("id")
            .eq("scientific_name", value: trimmedScientificName)
            .limit(1)
            .execute()
            .value

        return rows.first?.id
    }

    private func normalizedExploreScanGeoprivacy(_ value: String) -> String {
        switch value {
        case "open", "obscured", "private":
            return value
        default:
            return "private"
        }
    }

    private func normalizedExploreEcologyType(_ value: String) -> String {
        switch value {
        case "wild", "urban", "domesticated", "unknown":
            return value
        default:
            return "unknown"
        }
    }

    private func normalizedExploreInferenceTier(_ value: String?) -> String {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return "flash"
        }
        return trimmed
    }

    private func normalizedExploreConfidence(_ value: Double?) -> Double {
        min(1.0, max(0.0, value ?? 0.0))
    }

    private func normalizedExploreUserReviewState(
        rawValue: String?,
        userConfirmedIdentification: Bool,
        userIdentificationOverride: String?
    ) -> String {
        if let rawValue,
           ["unreviewed", "ai_confirmed", "user_overridden"].contains(rawValue) {
            return rawValue
        }
        if userConfirmedIdentification {
            return "ai_confirmed"
        }
        if userIdentificationOverride?.nilIfEmpty != nil {
            return "user_overridden"
        }
        return "unreviewed"
    }

    private func restoreExploreMediaObjectKeys(
        for scan: ExploreShareMediaSnapshot,
        includeImages: Bool = true,
        includeAudio: Bool = false
    ) async throws -> ExploreRestoreMediaObjectKeys {
        let restorableImagePaths = includeImages
            ? resolveRestorableImagePaths(for: scan)
            : []
        let restorableVideoPaths = resolveRestorableVideoPaths(for: scan)
        let restorableAudioPaths = includeAudio
            ? resolveRestorableAudioPaths(for: scan)
            : []
        let imageSizes: [Int]
        if restorableImagePaths.isEmpty,
           includeImages,
           scan.fallbackImageData?.isEmpty == false {
            imageSizes = [scan.fallbackImageData?.count ?? 0]
        } else {
            imageSizes = try restorableImagePaths.map {
                try MediaStagingContract.fileSizeBytes(
                    at: localExploreRestoreFileURL(for: $0)
                )
            }
        }
        let videoSizes = try restorableVideoPaths.map {
            try MediaStagingContract.fileSizeBytes(
                at: localExploreRestoreFileURL(for: $0)
            )
        }
        let audioSizes = try restorableAudioPaths.map {
            try MediaStagingContract.fileSizeBytes(
                at: localExploreRestoreFileURL(for: $0)
            )
        }
        try validateExploreRestoreMediaPayload(
            imageSizes: imageSizes,
            videoSizes: videoSizes,
            audioSizes: audioSizes
        )

        let imageObjectKeys = includeImages
            ? try await restoreExploreImageObjectKeys(
                for: scan,
                localImagePaths: restorableImagePaths
            )
            : []
        let videoObjectKeys = try await restoreExploreVideoObjectKeys(
            for: scan,
            localVideoPaths: restorableVideoPaths
        )
        let audioObjectKeys = includeAudio
            ? try await restoreExploreAudioObjectKeys(
                for: scan,
                localAudioPaths: restorableAudioPaths
            )
            : []
        return ExploreRestoreMediaObjectKeys(
            imageObjectKeys: imageObjectKeys,
            videoObjectKeys: videoObjectKeys,
            audioObjectKeys: audioObjectKeys
        )
    }

    private func restoreExploreImageObjectKeys(
        for scan: ExploreShareMediaSnapshot,
        localImagePaths: [String]
    ) async throws -> [String] {
        if localImagePaths.isEmpty {
            guard let fallbackImageData = scan.fallbackImageData,
                  !fallbackImageData.isEmpty else {
                return []
            }

            let fileName = MediaStagingContract.sanitizedFileName("\(scan.scanId)_explore_restore_live.webp")
            let uploadFiles = [
                makeScanShareRestoreUploadFile(
                    fileName: fileName,
                    mediaKind: .image,
                    contentType: "image/webp",
                    sizeBytes: fallbackImageData.count,
                    scanId: scan.scanId
                )
            ]
            let uploadUrls = try await generateUploadURLs(uploadFiles: uploadFiles)
            guard let uploadUrl = uploadUrls.first else {
                throw MerianError.invalidResponse
            }
            try await uploadToR2(url: uploadUrl.signedUrl, data: fallbackImageData, mimeType: "image/webp")
            return [uploadUrl.objectKey]
        }

        let fileNames = localImagePaths.enumerated().map { index, path in
            let ext = URL(fileURLWithPath: path).pathExtension
            let normalizedExt = ext.isEmpty ? "webp" : ext
            return MediaStagingContract.sanitizedFileName("\(scan.scanId)_explore_restore_\(index).\(normalizedExt)")
        }

        let uploadFiles = try zip(localImagePaths, fileNames).map { path, fileName in
            let fileURL = localExploreRestoreFileURL(for: path)
            return makeScanShareRestoreUploadFile(
                fileName: fileName,
                mediaKind: .image,
                contentType: exploreRestoreMimeType(for: fileURL),
                sizeBytes: try MediaStagingContract.fileSizeBytes(at: fileURL),
                scanId: scan.scanId
            )
        }

        let uploadUrls = try await generateUploadURLs(uploadFiles: uploadFiles)
        guard uploadUrls.count == localImagePaths.count else {
            throw MerianError.invalidResponse
        }

        let uploadPairs = Array(zip(localImagePaths, uploadUrls))
        let maxConcurrentUploads = 2

        try await withThrowingTaskGroup(of: Void.self) { group in
            var iterator = uploadPairs.makeIterator()
            var inFlight = 0

            func enqueueNext() {
                while inFlight < maxConcurrentUploads, let (path, uploadUrl) = iterator.next() {
                    inFlight += 1
                    group.addTask { [self] in
                        let fileURL = localExploreRestoreFileURL(for: path)
                        try await uploadToR2(
                            url: uploadUrl.signedUrl,
                            fileURL: fileURL,
                            mimeType: exploreRestoreMimeType(for: fileURL)
                        )
                    }
                }
            }

            enqueueNext()
            while try await group.next() != nil {
                inFlight -= 1
                enqueueNext()
            }
        }

        return uploadUrls.map { $0.objectKey }
    }

    private func restoreExploreVideoObjectKeys(
        for scan: ExploreShareMediaSnapshot,
        localVideoPaths: [String]
    ) async throws -> [String] {
        guard !localVideoPaths.isEmpty else { return [] }
        guard localVideoPaths.count <= MerianConfig.mediaStagingMaxVideoFilesPerRequest,
              localVideoPaths.count <= MerianConfig.mediaStagingMaxFilesPerRequest else {
            throw MerianError.payloadTooLarge
        }

        let uploadFiles = try localVideoPaths.enumerated().map { index, path in
            let fileURL = localExploreRestoreFileURL(for: path)
            let fileExtension = fileURL.pathExtension.isEmpty ? "mp4" : fileURL.pathExtension
            let fileName = MediaStagingContract.sanitizedFileName(
                "\(scan.scanId)_explore_restore_video_\(index).\(fileExtension)"
            )
            let sizeBytes = try MediaStagingContract.fileSizeBytes(at: fileURL)
            guard sizeBytes <= MerianConfig.videoPayloadMaxBytes else {
                throw MerianError.payloadTooLarge
            }
            return makeScanShareRestoreUploadFile(
                fileName: fileName,
                mediaKind: .video,
                contentType: StagedMediaKind.video.contentType(for: fileURL.path),
                sizeBytes: sizeBytes,
                scanId: scan.scanId
            )
        }

        let uploadUrls = try await generateUploadURLs(uploadFiles: uploadFiles)
        guard uploadUrls.count == localVideoPaths.count else {
            throw MerianError.invalidResponse
        }

        for (path, uploadUrl) in zip(localVideoPaths, uploadUrls) {
            let fileURL = localExploreRestoreFileURL(for: path)
            try await uploadToR2(
                url: uploadUrl.signedUrl,
                fileURL: fileURL,
                mimeType: StagedMediaKind.video.contentType(for: fileURL.path)
            )
        }

        return uploadUrls.map(\.objectKey)
    }

    private func restoreExploreAudioObjectKeys(
        for scan: ExploreShareMediaSnapshot,
        localAudioPaths: [String]
    ) async throws -> [String] {
        guard !localAudioPaths.isEmpty else { return [] }
        guard localAudioPaths.count <= MerianConfig.mediaStagingMaxAudioFilesPerRequest,
              localAudioPaths.count <= MerianConfig.mediaStagingMaxFilesPerRequest else {
            throw MerianError.payloadTooLarge
        }

        let uploadFiles = try localAudioPaths.enumerated().map { index, path in
            let fileURL = localExploreRestoreFileURL(for: path)
            let fileExtension = fileURL.pathExtension.isEmpty ? "wav" : fileURL.pathExtension
            let fileName = MediaStagingContract.sanitizedFileName(
                "\(scan.scanId)_explore_restore_audio_\(index).\(fileExtension)"
            )
            let sizeBytes = try MediaStagingContract.fileSizeBytes(at: fileURL)
            guard sizeBytes <= MerianConfig.audioPayloadMaxBytes else {
                throw MerianError.payloadTooLarge
            }
            return makeScanShareRestoreUploadFile(
                fileName: fileName,
                mediaKind: .audio,
                contentType: StagedMediaKind.audio.contentType(for: fileURL.path),
                sizeBytes: sizeBytes,
                scanId: scan.scanId
            )
        }

        let uploadUrls = try await generateUploadURLs(uploadFiles: uploadFiles)
        guard uploadUrls.count == localAudioPaths.count else {
            throw MerianError.invalidResponse
        }

        for (path, uploadUrl) in zip(localAudioPaths, uploadUrls) {
            let fileURL = localExploreRestoreFileURL(for: path)
            try await uploadToR2(
                url: uploadUrl.signedUrl,
                fileURL: fileURL,
                mimeType: StagedMediaKind.audio.contentType(for: fileURL.path)
            )
        }

        return uploadUrls.map(\.objectKey)
    }

    private func resolveRestorableImagePaths(for scan: ExploreShareMediaSnapshot) -> [String] {
        var candidatePaths = scan.imagePaths

        if candidatePaths.isEmpty, let coverImagePath = scan.coverImagePath {
            candidatePaths.append(coverImagePath)
        }

        var resolved: [String] = []
        for path in candidatePaths where !path.starts(with: "http") {
            let fileURL = localExploreRestoreFileURL(for: path)
            if FileManager.default.fileExists(atPath: fileURL.path), !resolved.contains(path) {
                resolved.append(path)
            }
        }

        return resolved
    }

    private func resolveRestorableVideoPaths(for scan: ExploreShareMediaSnapshot) -> [String] {
        var resolved: [String] = []
        for path in scan.videoPaths where !path.starts(with: "http") {
            let fileURL = localExploreRestoreFileURL(for: path)
            if FileManager.default.fileExists(atPath: fileURL.path), !resolved.contains(path) {
                resolved.append(path)
            }
        }
        return resolved
    }

    private func resolveRestorableAudioPaths(for scan: ExploreShareMediaSnapshot) -> [String] {
        var resolved: [String] = []
        for path in scan.audioPaths where !path.starts(with: "http") {
            let fileURL = localExploreRestoreFileURL(for: path)
            if FileManager.default.fileExists(atPath: fileURL.path), !resolved.contains(path) {
                resolved.append(path)
            }
        }
        return resolved
    }

    private func localExploreRestoreFileURL(for path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        if let url = URL(string: path), url.isFileURL {
            return url
        }
        return URL.documentsDirectory.appendingPathComponent(path)
    }

    private func exploreRestoreMimeType(for fileURL: URL) -> String {
        let fileExtension = fileURL.pathExtension.lowercased()
        if fileExtension == "jpg" || fileExtension == "jpeg" {
            return "image/jpeg"
        }
        if fileExtension == "png" {
            return "image/png"
        }
        if fileExtension == "heic" || fileExtension == "heif" {
            return "image/heic"
        }

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return "image/webp"
        }
        defer { try? handle.close() }

        let prefixData: Data
        do {
            guard let readData = try handle.read(upToCount: 12) else {
                return "image/webp"
            }
            prefixData = readData
        } catch {
            return "image/webp"
        }
        let prefix = [UInt8](prefixData)
        if prefix.count >= 3,
           prefix[0] == 0xFF, prefix[1] == 0xD8, prefix[2] == 0xFF {
            return "image/jpeg"
        }
        if prefix.count >= 8,
           prefix[0] == 0x89, prefix[1] == 0x50, prefix[2] == 0x4E, prefix[3] == 0x47,
           prefix[4] == 0x0D, prefix[5] == 0x0A, prefix[6] == 0x1A, prefix[7] == 0x0A {
            return "image/png"
        }
        if prefix.count >= 12,
           prefix[0] == 0x52, prefix[1] == 0x49, prefix[2] == 0x46, prefix[3] == 0x46,
           prefix[8] == 0x57, prefix[9] == 0x45, prefix[10] == 0x42, prefix[11] == 0x50 {
            return "image/webp"
        }
        return "image/webp"
    }
}
