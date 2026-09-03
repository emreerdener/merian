import Foundation
import Testing
import UIKit

@testable import Merian

/// Shared request evidence for these five operations only. Production endpoint
/// ownership remains separated into ScanEnrichment, Exports, and ProductFeedback.
struct EnrichmentExportFeedbackRequestCase: Sendable {
    enum Kind: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case deferredContext, enrichment, export, survey, communityFeedback
        var testDescription: String { rawValue }
    }

    static let scanID = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
    static let responseJSON = """
    {"success":true,"data":{"habitat_description":"Synthetic habitat.","gbif_taxon_key":42,
    "alternative_common_names":["Synthetic synonym"],
    "similar_species":[{"scientific_name":"Testus example","common_name":"Synthetic species"}]}}
    """

    let kind: Kind
    let function: String
    let expectedJSON: String
    let invoke: @MainActor @Sendable (MerianNetworkClient) async throws -> Void

    var path: String { "/\(function)" }
    var timeout: TimeInterval { kind == .deferredContext || kind == .export ? 15 : 30 }
    var idempotencyKey: String? { kind == .enrichment ? Self.scanID.lowercased() : nil }

    @MainActor
    static func make(
        _ kind: Kind,
        enrichmentScope: String = "lookalikes",
        exportScope: String? = nil
    ) throws -> Self {
        let function: String
        let payload: [String: Any]
        let invoke: @MainActor @Sendable (MerianNetworkClient) async throws -> Void
        switch kind {
        case .deferredContext:
            function = "update-scan-context"
            payload = ["scan_id": " Raw-Scan ", "weather_condition": " Clear \n"]
            invoke = { client in
                try await client.updateDeferredScanContext(
                    scanId: " Raw-Scan ", telemetry: telemetry(condition: " Clear \n")
                )
            }
        case .enrichment:
            function = "enrich-scan"
            payload = [
                "scan_id": scanID, "scientific_name": " Testus example ", "confidence_score": 0.0,
                "inference_tier": " RAW-TIER ", "scope": enrichmentScope
            ]
            invoke = { client in
                _ = try await client.fetchEnrichment(
                    scanId: scanID, scientificName: " Testus example ", confidenceScore: 0,
                    inferenceTier: " RAW-TIER ", scope: enrichmentScope
                )
            }
        case .export:
            function = "request-export-dwca"
            payload = ["exportScope": exportScope ?? "personal", "includePreciseCoordinates": true]
            invoke = { client in
                if let exportScope {
                    try await client.requestDwcAExport(scope: exportScope)
                } else {
                    try await client.requestDwcAExport()
                }
            }
        case .survey:
            function = "submit-feedback-survey"
            let submission = survey()
            payload = [
                "survey_campaign_id": FeedbackSurveyCampaign.currentId,
                "satisfaction_rating": 5, "recommendation_rating": 0,
                "used_features": ["browse_explore", "identify_found_subject"],
                "most_useful_features": ["insight_sheet", "camera_identification"],
                "confusing_or_disappointing": "", "wished_next": "Synthetic request",
                "bug_status": "blocked", "bug_details": "", "may_follow_up": false, "contact": "",
                "app_version": appVersion, "build_number": buildNumber, "platform": "ios",
                "device_model": UIDevice.current.model, "os_version": UIDevice.current.systemVersion,
                "locale": Locale.current.identifier, "timezone": TimeZone.current.identifier
            ]
            invoke = { client in try await client.submitFeedbackSurvey(submission) }
        case .communityFeedback:
            function = "submit-community-feedback"
            payload = [
                "feedback": "Synthetic community feedback", "app_version": appVersion,
                "build_number": buildNumber, "platform": "ios", "os_version": UIDevice.current.systemVersion
            ]
            invoke = { client in
                try await client.submitCommunityFeedback(feedback: " \n Synthetic community feedback \t ")
            }
        }
        let encodedPayload = try JSONSerialization.data(withJSONObject: payload)
        return Self(
            kind: kind, function: function,
            expectedJSON: try #require(String(data: encodedPayload, encoding: .utf8)),
            invoke: invoke
        )
    }

    @discardableResult
    func expectRequest(_ request: URLRequest) throws -> NetworkEndpointRequestSnapshot {
        try NetworkEndpointTestSupport.expectPOST(
            request, function: function, json: expectedJSON, timeout: timeout, idempotencyKey: idempotencyKey
        )
    }

    @MainActor
    func withResponse(
        _ json: String = Self.responseJSON,
        status: Int = 200,
        body: (MerianNetworkClient) async throws -> Void
    ) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        try await confirmation("One endpoint request") { sent in
            fixture.transport.register(path: path) { request in
                sent()
                try expectRequest(request)
                return try NetworkEndpointTestSupport.response(to: request, status: status, json: json)
            }
            try await body(fixture.client)
        }
    }

    static func telemetry(
        elevation: Double? = nil,
        condition: String? = nil,
        temperature: Double? = nil,
        location: String? = nil
    ) -> CaptureTelemetry {
        CaptureTelemetry(
            subjectDistanceInMeters: nil, gpsLatitude: nil, gpsLongitude: nil, gpsElevation: elevation,
            locationName: location, weatherCondition: condition, weatherTemperatureF: temperature,
            timeOfDay: nil, timestamp: nil, zoomFactor: nil, estimatedSizeCm: nil
        )
    }

    @MainActor
    private static func survey() -> FeedbackSurveySubmission {
        FeedbackSurveySubmission(
            satisfactionRating: 5, recommendationRating: 0,
            usedFeatures: [.browseExplore, .identifyFoundSubject],
            mostUsefulFeatures: [.insightSheet, .cameraIdentification],
            confusingOrDisappointing: " \n\t ", wishedNext: "  Synthetic request \n",
            bugStatus: .blocked, bugDetails: " \n", mayFollowUp: false, contact: " \t"
        )
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }
}
