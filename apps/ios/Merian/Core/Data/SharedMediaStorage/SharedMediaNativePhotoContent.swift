import Foundation

/// Inactive content declaration, never received-state, byte-verification or dispatch authority.
/// A consuming operation must separately check the current native receiving/account fences.
struct SharedMediaNativePhotoContent: Sendable {
    struct Role: Sendable {
        let referenceID: UUID
        let byteCount: Int64
        let sha256: String
        let contentType: String
    }
    struct Photo: Sendable {
        let source: Role
        let ai: Role
        let display: Role
        let recipe: SharedMediaNativePreparationRecipe
    }
    let canonicalBytes: Data
    let unverifiedDigest: String

    /// Only saved values are projected. No media reads, live controls or identity creation.
    init(prepared: SharedMediaNativeReceivingIntent.Prepared) throws {
        _ = try prepared.encoded()
        guard prepared.format == .preparedV2, prepared.version == 2 else { throw SharedMediaStorageFailure.invalid }
        let frozen = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
        let supporting: SharedMediaNativeFrozenSupporting = try SharedMediaAcquisitionEncoding.decode(
            frozen.supportingBytes, maximum: Int(PhotoPreparationPolicy.metadata))
        let photos = try frozen.entries.map { entry -> Photo in
            let intent = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes)
            let original = intent.preparation.original
            return .init(source: .init(referenceID: original.reference.referenceID, byteCount: original.byteCount,
                sha256: original.sha256, contentType: original.contentType),
                ai: .init(referenceID: intent.ai.referenceID, byteCount: intent.ai.byteCount,
                    sha256: intent.ai.sha256, contentType: intent.ai.contentType),
                display: .init(referenceID: intent.display.referenceID, byteCount: intent.display.byteCount,
                    sha256: intent.display.sha256, contentType: intent.display.contentType), recipe: intent.preparation.recipe)
        }
        try self.init(scanID: prepared.observationID, packageID: frozen.packageID,
            photos: photos, contexts: supporting.contexts)
    }

    /// Typed claims for the closed v1 schema; these values carry no local or remote authority.
    init(scanID: UUID, packageID: UUID, photos: [Photo], contexts: [ObservationContext]) throws {
        guard (1...2).contains(photos.count) else { throw SharedMediaStorageFailure.invalid }
        _ = try PhotoPreparationPolicy.contexts(contexts)
        var references = Set<UUID>()
        for photo in photos {
            try photo.recipe.validate()
            for (role, limit) in [(photo.source, PhotoPreparationPolicy.original),
                                  (photo.ai, PhotoPreparationPolicy.aiCohort), (photo.display, PhotoPreparationPolicy.display)] {
                guard references.insert(role.referenceID).inserted, role.byteCount > 0, role.byteCount <= limit,
                      SharedMediaAcquisitionEncoding.isHash(role.sha256), !role.contentType.isEmpty,
                      role.contentType.utf8.count <= 128, !role.contentType.unicodeScalars.contains(where: { $0.value == 0 }) else {
                    throw SharedMediaStorageFailure.invalid
                }
            }
        }
        let originals = try PhotoPreparationPolicy.add(photos.map(\.source.byteCount))
        let ai = try PhotoPreparationPolicy.add(photos.map(\.ai.byteCount))
        let display = try PhotoPreparationPolicy.add(photos.map(\.display.byteCount))
        guard originals <= PhotoPreparationPolicy.originalCohort, ai <= PhotoPreparationPolicy.aiCohort,
              display <= PhotoPreparationPolicy.displayCohort else { throw PhotoPreparationFailure.sizeLimit }
        let contextJSON = contexts.map { "{\"text_utf8_base64\":" + Self.quote(Data($0.freeText.utf8).base64EncodedString()) + "}" }
        let photoJSON = photos.enumerated().map { Self.photo($0.element, ordinal: $0.offset) }
        // Explicit ASCII field order is the executable Deno schema's canonical order.
        // No generic JSON canonicalizer or Foundation float/Unicode normalization.
        let text = "{\"contexts\":[" + contextJSON.joined(separator: ",")
            + "],\"contract\":\"client_prepared_media_v1\",\"kind\":\"initial_photo\",\"package_id\":"
            + Self.quote(packageID.uuidString.lowercased()) + ",\"photos\":[" + photoJSON.joined(separator: ",")
            + "],\"resource_profile\":\"P1-L1\",\"scan_id\":" + Self.quote(scanID.uuidString.lowercased()) + ",\"version\":1}"
        let bytes = Data(text.utf8)
        guard bytes.count <= PhotoPreparationPolicy.metadata,
              try PhotoPreparationPolicy.add([originals, ai, display, Int64(bytes.count)]) <= PhotoPreparationPolicy.package else {
            throw PhotoPreparationFailure.sizeLimit
        }
        canonicalBytes = bytes
        unverifiedDigest = SharedMediaAcquisitionEncoding.digest(
            Data("merian.initial-analysis.cpm-photo-content.v1\n".utf8) + bytes)
    }

    private static func photo(_ p: Photo, ordinal: Int) -> String {
        "{\"ai\":" + role(p.ai) + ",\"display\":" + role(p.display) + ",\"ordinal\":" + String(ordinal)
            + ",\"recipe\":" + recipe(p.recipe) + ",\"source\":" + role(p.source) + "}"
    }
    private static func role(_ r: Role) -> String {
        "{\"byte_count\":" + String(r.byteCount) + ",\"declared_content_type\":" + quote(r.contentType)
            + ",\"reference_id\":" + quote(r.referenceID.uuidString.lowercased()) + ",\"sha256\":" + quote(r.sha256) + "}"
    }
    private static func bits(_ value: Double?) -> String {
        guard let value else { return "null" }
        let hex = String(value.bitPattern, radix: 16)
        return quote(String(repeating: "0", count: 16 - hex.count) + hex)
    }
    private static func recipe(_ r: SharedMediaNativePreparationRecipe) -> String {
        "{\"camera_vertical_center_bits\":" + bits(r.cameraVerticalCenter)
            + ",\"crop_display_size_bits\":" + bits(r.cropDisplaySize) + ",\"format\":" + quote(r.format.rawValue)
            + ",\"is_pro\":" + (r.isPro ? "true" : "false") + ",\"offset_x_bits\":" + bits(r.offsetX)
            + ",\"offset_y_bits\":" + bits(r.offsetY) + ",\"quarter_turns\":" + String(r.quarterTurns)
            + ",\"scale_bits\":" + bits(r.scale) + "}"
    }
    /// JSON.stringify scalar spelling: slash and non-control Unicode remain exact.
    static func quote(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x22: result += "\\\""
            case 0x5c: result += "\\\\"
            case 8: result += "\\b"
            case 9: result += "\\t"
            case 10: result += "\\n"
            case 12: result += "\\f"
            case 13: result += "\\r"
            case 0..<32:
                let hex = String(scalar.value, radix: 16)
                result += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}
