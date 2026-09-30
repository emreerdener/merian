import Foundation

/// A denial-only expectation of the app's assignment, never a provider selector.
enum IdentificationRecipientExpectation: String, Codable, Sendable {
    case gemini = "google_gemini"
    case openAI = "openai"
    case recoveryOnly = "recovery_only"

    static let header = "X-Merian-Identification-Recipient"
}

struct IdentificationDispatchAuthorization: Sendable {
    static let protocolHeader = "X-Merian-Identification-Protocol"
    /// Explicit primary rank and verified review across all consumers; independent of entitlement protocol 3.
    static let currentProtocol = 5
    let identificationProtocol = Self.currentProtocol
    let recipient: IdentificationRecipientExpectation
    let validate: @MainActor @Sendable () throws -> Void
}

/// Derived off-main from the exact, bounded JSON that will be sent. Only shape
/// metadata is encoded into the read-only RPC, never observation content.
struct IdentificationPreflightInput: Encodable, Equatable, Sendable {
    enum Profile: String, Codable, Sendable {
        case vision = "vision_compat_v1"
        case text = "multimodal_text_v1"
        case photo = "multimodal_photo_v1"
        case audio = "multimodal_audio_v1"
        case photoAudio = "multimodal_photo_audio_v1"
        case videoFrames = "multimodal_video_frames_v1"
        case videoAudio = "multimodal_video_audio_v1"
    }

    let inputProfile: Profile
    let flashFallbackEligible: Bool
    let originalAnalysisID: UUID
    let operation = "scan_identification"
    let clientProtocol = 3
    let identificationProtocol = IdentificationDispatchAuthorization.currentProtocol

    enum CodingKeys: String, CodingKey {
        case inputProfile = "p_input_profile"
        case flashFallbackEligible = "p_flash_fallback_eligible"
        case originalAnalysisID = "p_original_analysis_id"
        case operation = "p_operation"
        case clientProtocol = "p_client_protocol"
        case identificationProtocol = "p_identification_protocol"
    }

    init(body: Data, function: String) throws {
        guard let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let id = payload["client_scan_id"] as? String,
              let scanID = UUID(uuidString: id),
              ["identify", "identify-multimodal"].contains(function) else {
            throw MerianError.invalidResponse
        }
        func count(_ key: String) throws -> Int {
            guard let value = payload[key] else { return 0 }
            guard let values = value as? [String] else { throw MerianError.invalidResponse }
            return values.count
        }
        let inlineImages = try count("imageBase64s")
        let images = try inlineImages > 0 ? inlineImages : count("r2ObjectKeys")
        let inlineAudio = try count("audioBase64s")
        let audio = try inlineAudio > 0 ? inlineAudio : count("audioR2ObjectKeys")
        let videoObjects = try count("videoR2ObjectKeys")
        let visuals = payload["visualMediaItems"] as? [[String: Any]] ?? []
        let visualKinds = visuals.compactMap { $0["kind"] as? String }
        let validVisuals = visuals.count == images && visualKinds.count == images
            && visualKinds.allSatisfy { $0 == "image" || $0 == "video_frame" }
        let visualVideo = videoObjects > 0 || (validVisuals
            ? visualKinds.contains("video_frame")
            : (payload["videoFrameCount"] as? Int ?? 0) > 0)
        let audioItems = payload["audioMediaItems"] as? [[String: Any]] ?? []
        let audioKinds = audioItems.compactMap { $0["kind"] as? String }
        let audioVideo = audioItems.count == audio && audioKinds.count == audio
            && audioKinds.allSatisfy { $0 == "audio" || $0 == "video_audio" }
            && audioKinds.contains("video_audio")
        let descriptions: Int
        if function == "identify" {
            inputProfile = .vision
            descriptions = (payload["description"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? 1 : 0
        } else {
            inputProfile = visualVideo || audioVideo ? (audio > 0 ? .videoAudio : .videoFrames)
                : images > 0 ? (audio > 0 ? .photoAudio : .photo)
                : audio > 0 ? .audio : .text
            descriptions = (payload["observation_contexts"] as? [[String: Any]] ?? [])
                .filter { context in
                    ((context["freeText"] ?? context["free_text"]) as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                }.count
        }
        flashFallbackEligible = IdentificationEvidenceAllowance.permitsFreeScan(
            images: images, audio: audio, descriptions: descriptions,
            videos: visualVideo || audioVideo ? 1 : 0
        )
        originalAnalysisID = scanID
    }
}

struct IdentificationPreflightResponse: Decodable, Sendable {
    enum Decision: String, Decodable, Sendable {
        case ready
        case permissionRequired = "permission_required"
        case clientUpdateRequired = "client_update_required"
        case recoveryOnly = "recovery_only"
    }
    let inputProfile: IdentificationPreflightInput.Profile
    let decision: Decision
    let processorPermission: IdentificationRecipientExpectation?
    let minimumClientProtocol: Int?
    let minimumIdentificationProtocol: Int?

    enum CodingKeys: String, CodingKey {
        case inputProfile = "input_profile"
        case decision
        case processorPermission = "processor_permission"
        case minimumClientProtocol = "minimum_client_protocol"
        case minimumIdentificationProtocol = "minimum_identification_protocol"
    }

    static func recipient(from data: Data, for input: IdentificationPreflightInput) throws
        -> IdentificationRecipientExpectation {
        guard data.count <= 8_192 else { throw MerianError.invalidResponse }
        let rows = try JSONDecoder().decode([Self].self, from: data)
        guard rows.count == 1, let row = rows.first, row.inputProfile == input.inputProfile else {
            throw MerianError.invalidResponse
        }
        if row.decision == .recoveryOnly {
            guard row.processorPermission == nil, row.minimumClientProtocol == nil,
                  row.minimumIdentificationProtocol == nil else {
                throw MerianError.invalidResponse
            }
            return .recoveryOnly
        }
        guard let minimum = row.minimumClientProtocol, (0...1000).contains(minimum),
              row.processorPermission != .recoveryOnly else { throw MerianError.invalidResponse }
        if let identificationMinimum = row.minimumIdentificationProtocol,
           !(0...1000).contains(identificationMinimum) { throw MerianError.invalidResponse }
        if row.decision == .clientUpdateRequired {
            guard minimum > 0 || (row.minimumIdentificationProtocol ?? 0) > 0 else {
                throw MerianError.invalidResponse
            }
            throw MerianError.httpError(statusCode: 426, message: #"{"code":"client_update_required"}"#)
        }
        guard minimum <= input.clientProtocol,
              let identificationMinimum = row.minimumIdentificationProtocol,
              [0, 4, 5].contains(identificationMinimum),
              identificationMinimum <= input.identificationProtocol,
              let recipient = row.processorPermission,
              recipient != .openAI || [4, 5].contains(identificationMinimum) else {
            throw MerianError.invalidResponse
        }
        if row.decision == .permissionRequired {
            throw recipient == .openAI ? MerianError.openAIConsentRequired : MerianError.aiConsentRequired
        }
        return recipient
    }
}

struct PreparedIdentificationPayload: Sendable {
    let data: Data
    let preflight: IdentificationPreflightInput

    init(data: Data, function: String) throws {
        self.data = data
        preflight = try IdentificationPreflightInput(body: data, function: function)
    }
}
