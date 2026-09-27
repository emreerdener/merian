import Foundation
import Testing

@testable import Merian

@Suite("Identification Recipient Preflight")
struct IdentificationPreflightTests {
    private let scanID = "11111111-1111-4111-8111-111111111111"

    @Test func inputUsesOnlyShapeAndOriginalScanIdentity() throws {
        let input = try makeInput([
            "imageBase64s": ["synthetic-image"], "description": "synthetic observation",
            "gpsLatitude": 0, "user_id": "untrusted-owner", "provider": "untrusted-selector",
            "parent_scan_id": "22222222-2222-4222-8222-222222222222"
        ])
        let data = try JSONEncoder().encode(input)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == Set([
            "p_operation", "p_input_profile", "p_flash_fallback_eligible",
            "p_original_analysis_id", "p_client_protocol", "p_identification_protocol"
        ]))
        #expect((object["p_original_analysis_id"] as? String)?.lowercased() == scanID)
        #expect(object["p_input_profile"] as? String == "multimodal_photo_v1")
        #expect(object["p_client_protocol"] as? Int == 3)
        #expect(object["p_identification_protocol"] as? Int == 4)
        #expect(!String(decoding: data, as: UTF8.self).contains("synthetic"))
    }

    @Test func completeEvidenceDeterminesProfileAndFlashEligibility() throws {
        let cases: [([String: Any], IdentificationPreflightInput.Profile, Bool)] = [
            (["observation_contexts": [["freeText": "bird"]]], .text, true),
            (["observation_contexts": [["free_text": "bird"], ["freeText": "  "]]], .text, true),
            (["imageBase64s": ["image"]], .photo, true),
            (["r2ObjectKeys": ["image1", "image2"]], .photo, false),
            (["imageBase64s": ["image"], "r2ObjectKeys": ["old1", "old2"]], .photo, true),
            (["audioBase64s": ["audio"]], .audio, true),
            (["audioR2ObjectKeys": ["audio"]], .audio, true),
            (["imageBase64s": ["image"], "audioBase64s": ["audio"]], .photoAudio, false),
            (["imageBase64s": ["frame"], "videoFrameCount": 1], .videoFrames, false),
            (["imageBase64s": ["frame"], "visualMediaItems": [["kind": "video_frame"]]], .videoFrames, false),
            (["imageBase64s": ["image"], "visualMediaItems": [["kind": "image"]], "videoFrameCount": 1], .photo, true),
            (["videoR2ObjectKeys": ["video"], "audioR2ObjectKeys": ["audio"]], .videoAudio, false),
            (["imageBase64s": ["image"], "audioR2ObjectKeys": ["audio"], "audioMediaItems": [["kind": "video_audio"]]], .videoAudio, false),
            (["imageBase64s": ["image"], "observation_contexts": [["freeText": "description"]]], .photo, true)
        ]
        for (payload, profile, flash) in cases {
            let input = try makeInput(payload)
            #expect(input.inputProfile == profile)
            #expect(input.flashFallbackEligible == flash)
        }
        let legacy = try makeInput(["imageBase64s": ["image"]], function: "identify")
        #expect(legacy.inputProfile == .vision)
        #expect(legacy.flashFallbackEligible)
        #expect((try makeInput(["imageBase64s": ["image"], "description": "leaf"], function: "identify")).flashFallbackEligible)
    }

    @Test func malformedIdentityCannotStartPreflight() throws {
        for id in ["", "not-a-uuid"] {
            let data = try JSONSerialization.data(withJSONObject: ["client_scan_id": id])
            #expect(throws: MerianError.invalidResponse) {
                try IdentificationPreflightInput(body: data, function: "identify")
            }
        }
    }

    @Test func responseMustBeOneClosedDecisionForExactProfile() throws {
        let input = try makeInput(["imageBase64s": ["image"]])
        for recipient in ["google_gemini", "openai"] {
            let response = row(decision: "ready", recipient: recipient, minimum: 3)
            #expect(try IdentificationPreflightResponse.recipient(from: response, for: input).rawValue == recipient)
        }
        #expect(try IdentificationPreflightResponse.recipient(
            from: row(decision: "recovery_only"), for: input
        ) == .recoveryOnly)
        #expect(throws: MerianError.openAIConsentRequired) {
            try IdentificationPreflightResponse.recipient(
                from: row(decision: "permission_required", recipient: "openai", minimum: 3), for: input)
        }
        #expect(throws: MerianError.aiConsentRequired) {
            try IdentificationPreflightResponse.recipient(
                from: row(decision: "permission_required", recipient: "google_gemini", minimum: 0), for: input)
        }
        #expect(throws: MerianError.httpError(statusCode: 426, message: #"{"code":"client_update_required"}"#)) {
            try IdentificationPreflightResponse.recipient(
                from: row(decision: "client_update_required", minimum: 4), for: input)
        }
        let invalid = [
            Data("[]".utf8), Data("{}".utf8), Data(repeating: 32, count: 8_193),
            row(decision: "unknown"), row(decision: "ready"),
            row(decision: "ready", recipient: "other", minimum: 0),
            row(decision: "ready", recipient: "google_gemini", minimum: 4),
            row(decision: "ready", recipient: "recovery_only", minimum: 0),
            row(decision: "ready", recipient: "google_gemini", minimum: 0, profile: "multimodal_audio_v1"),
            row(decision: "recovery_only", recipient: "google_gemini"),
            row(decision: "recovery_only", minimum: 0),
            row(decision: "client_update_required", minimum: 0)
        ]
        for data in invalid {
            #expect(throws: (any Error).self) {
                try IdentificationPreflightResponse.recipient(from: data, for: input)
            }
        }
    }

    private func makeInput(_ payload: [String: Any], function: String = "identify-multimodal") throws -> IdentificationPreflightInput {
        var payload = payload
        payload["client_scan_id"] = scanID
        return try IdentificationPreflightInput(body: JSONSerialization.data(withJSONObject: payload), function: function)
    }

    @Test func identificationCapabilityIsIndependentOfEntitlementAndCannotBeGuessed() throws {
        let input = try makeInput(["imageBase64s": ["image"]])
        func response(_ decision: String, minimum: Int) -> Data {
            Data("[{\"input_profile\":\"multimodal_photo_v1\",\"decision\":\"\(decision)\",\"processor_permission\":\"openai\",\"minimum_client_protocol\":3,\"minimum_identification_protocol\":\(minimum)}]".utf8)
        }
        #expect(try IdentificationPreflightResponse.recipient(from: response("ready", minimum: 4), for: input) == .openAI)
        for minimum in [0, 1, 2, 3, 5] {
            #expect(throws: MerianError.invalidResponse) {
                try IdentificationPreflightResponse.recipient(from: response("ready", minimum: minimum), for: input)
            }
        }
        #expect(throws: MerianError.httpError(statusCode: 426, message: #"{"code":"client_update_required"}"#)) {
            try IdentificationPreflightResponse.recipient(from: response("client_update_required", minimum: 5), for: input)
        }
        for recipient in ["google_gemini", "openai"] {
            for decision in ["ready", "permission_required"] {
                for capability in ["", ",\"minimum_identification_protocol\":null"] {
                    let data = Data("[{\"input_profile\":\"multimodal_photo_v1\",\"decision\":\"\(decision)\",\"processor_permission\":\"\(recipient)\",\"minimum_client_protocol\":3\(capability)}]".utf8)
                    #expect(throws: MerianError.invalidResponse) {
                        try IdentificationPreflightResponse.recipient(from: data, for: input)
                    }
                }
            }
        }
    }

    private func row(decision: String, recipient: String? = nil, minimum: Int? = nil,
                     profile: String = "multimodal_photo_v1") -> Data {
        let recipientJSON = recipient.map { "\"\($0)\"" } ?? "null"
        let minimumJSON = minimum.map(String.init) ?? "null"
        let identificationMinimum = decision == "recovery_only" || recipient == nil
            ? "null" : recipient == "openai" ? "4" : "0"
        return Data("[{\"input_profile\":\"\(profile)\",\"decision\":\"\(decision)\",\"processor_permission\":\(recipientJSON),\"minimum_client_protocol\":\(minimumJSON),\"minimum_identification_protocol\":\(identificationMinimum)}]".utf8)
    }
}
