import Foundation

/// Initial-result mapping and receipt projection on the existing stateless factory.
extension LocalScanRecordFactory {
    /// An unsaved original-result projection only. The receiving owner must bind
    /// capture metadata, reserve storage and atomically transfer media/queue state.
    /// Replays must never call this over a later edited or enrolled scan.
    static func makeInitialRecord(
        from result: InitialRetainedResult, speciesID: String,
        timestamp: Date, captureDate: Date, capturedMediaJSON: String?,
        coverImagePath: String?, fieldNotes: String?
    ) throws -> LocalScanRecord {
        let mapped = try initialSpeciesData(result)
        guard let scanID = mapped.scanId, timestamp.timeIntervalSince1970.isFinite,
              captureDate.timeIntervalSince1970.isFinite else { throw InitialAnalysisCanonical.Invalid.document }
        let record = makeRecord(from: mapped, recordId: scanID, speciesId: speciesID,
            timestamp: timestamp, captureDate: captureDate, capturedMediaJSON: capturedMediaJSON,
            coverImagePath: coverImagePath, isLiveCapture: mapped.isLiveCapture, fieldNotes: fieldNotes)
        // Enrollment compares these exact original server projections. Domain
        // candidate spelling/display filtering must not rewrite that evidence.
        record.candidatesData = try result.applicationFieldJSON("candidates")
        record.petIdentificationData = try result.applicationFieldJSON("pet_identification")
        record.wikipediaOverview = mapped.wikipediaOverview
        return record
    }

    /// Historical first-application baseline, not an enrolled analysis snapshot.
    /// The evidence UUID namespaces the display encoding; it never becomes a
    /// selected/enrolled analysis ID. Later replay must not restore this display.
    @MainActor
    static func initialApplicationBaseline(record: LocalScanRecord, result: InitialRetainedResult) throws -> Data {
        guard let reference = try InitialAnalysisCanonical.parse(result.reference).object,
              reference["scan_id"]?.string == record.id,
              let evidence = reference["result_evidence_id"]?.string.flatMap(UUID.init(uuidString:)),
              record.analysisOwnerAccountID == nil, record.selectedAnalysisID == nil,
              record.observationStateRevision == nil, record.analysisSelectionInitialized else {
            throw SharedMediaStorageFailure.conflict
        }
        // Never fault relationship arrays in this stateless projection. The
        // atomic owner must prove relation absence through bounded scoped reads.
        func value<T: Encodable>(_ value: T) throws -> Data {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(value)
        }
        // The existing display allowlist supplies every mapped result field.
        // All remaining persisted scan scalars are explicit below, including
        // absent review/enrichment/location facts and immutable submitted text.
        let fields: [String: Data] = try [
            "version": value(1), "id": value(record.id), "resultEvidenceID": value(evidence),
            "resultDigest": value(result.resultDigest), "provenanceDigest": value(result.provenanceDigest),
            "display": AnalysisDisplaySnapshot(analysisID: evidence, record: record).storedData(),
            "mediaAuthorityRaw": value(record.mediaAuthorityRaw), "sharedMediaConsumerID": value(record.sharedMediaConsumerID),
            "timestampBits": value(record.timestamp.timeIntervalSinceReferenceDate.bitPattern),
            "captureDateBits": value(record.captureDate?.timeIntervalSinceReferenceDate.bitPattern),
            "capturedMediaJSON": value(record.capturedMediaJSON), "coverImagePath": value(record.coverImagePath),
            "isLiveCapture": value(record.isLiveCapture), "isLocallyArchived": value(record.isLocallyArchived),
            "locationName": value(record.locationName), "weatherCondition": value(record.weatherCondition),
            "weatherTemperatureF": value(record.weatherTemperatureF), "similarSpecies": value(record.similarSpecies),
            "lookalikesData": value(record.lookalikesData), "userIdentificationOverride": value(record.userIdentificationOverride),
            "userConfirmedIdentification": value(record.userConfirmedIdentification), "isFlagged": value(record.isFlagged),
            "gpsLatitude": value(record.gpsLatitude), "gpsLongitude": value(record.gpsLongitude),
            "gpsElevation": value(record.gpsElevation), "zoomFactor": value(record.zoomFactor),
            "confirmedSpeciesIdentityData": value(record.confirmedSpeciesIdentityData),
            "aiIdentificationReviewData": value(record.aiIdentificationReviewData), "customTags": value(record.customTags),
            "hasBeenViewed": value(record.hasBeenViewed), "confirmedSpeciesId": value(record.confirmedSpeciesId),
            "userReviewStateRaw": value(record.userReviewStateRaw), "observationContextsJSON": value(record.observationContextsJSON),
            "fieldNotes": value(record.fieldNotes)
        ]
        let bytes = try value(fields)
        guard bytes.count <= SharedMediaNativeConsumerCohort.InitialApplicationReceipt.maximumBaselineBytes else {
            throw SharedMediaStorageFailure.capacity
        }
        return bytes
    }

    /// Uses frozen result-v1 fields directly, then the existing domain/factory
    /// presentation rules. No EdgeResponse decoding or current-account inference.
    private static func initialSpeciesData(_ result: InitialRetainedResult) throws -> SpeciesData {
        let fields = try result.applicationFields
        func text(_ key: String) -> String? { fields[key]?.string }
        func number(_ key: String) -> Double? { fields[key]?.string.flatMap(Double.init) }
        func strings(_ key: String) -> [String]? { fields[key]?.array?.compactMap(\.string) }
        func integer(_ key: String) -> Int? { fields[key]?.integer.flatMap(Int.init(exactly:)) }
        let provenance = IdentificationResultProvenance(storedData: try result.applicationProvenance())
        let primary: PrimaryIdentification?
        if let value = fields["primary_identification"] {
            let decoded = PrimaryIdentification(storedData: try InitialAnalysisCanonical.encode(value))
            guard decoded.value != nil, provenance.requiresPrimaryIdentification else { throw InitialAnalysisCanonical.Invalid.document }
            primary = decoded
        } else {
            guard !provenance.requiresPrimaryIdentification else { throw InitialAnalysisCanonical.Invalid.document }
            primary = nil
        }
        let common = primary?.value.map { $0.commonName ?? $0.scientificName ?? "Unknown Subject" }
            ?? text("common_name")?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown Subject"
        let scientific = primary?.value?.scientificName ?? text("scientific_name") ?? "Taxonomy Unavailable"
        guard let confidence = number("confidence_score"), let biological = fields["is_biological_subject"]?.boolean,
              let live = fields["is_live_capture"]?.boolean else { throw InitialAnalysisCanonical.Invalid.document }
        let resolved = biological && (primary == nil || primary?.value?.resolution == .species)
            && SpeciesIdentificationResolutionPolicy.isResolved(scientific) && SpeciesIdentificationResolutionPolicy.isResolved(common)
        let speciesDetails = resolved && !HumanSubjectIdentityPolicy.matches(commonName: common, scientificNames: [scientific])
        let taxonomy = fields["taxonomy"]?.object, insight = fields["insight_data"]?.object
        let pet: PetIdentification?
        if speciesDetails, let object = fields["pet_identification"]?.object {
            guard let group = object["species_group"]?.string, let label = object["label"]?.string,
                  let kind = object["label_type"]?.string, let score = object["confidence_score"]?.string.flatMap(Double.init),
                  let evidence = object["evidence"]?.array else { throw InitialAnalysisCanonical.Invalid.document }
            pet = .init(speciesGroup: group, label: label, labelType: kind, confidenceScore: score, evidence: evidence.compactMap(\.string))
        } else { pet = nil }
        let candidates: [IdentificationCandidate]?
        if speciesDetails, let items = fields["candidates"]?.array {
            candidates = try items.map { value in
                guard let object = value.object, let name = object["scientific_name"]?.string,
                      let score = object["confidence_score"]?.string.flatMap(Double.init) else { throw InitialAnalysisCanonical.Invalid.document }
                return .init(scientificName: name,
                    commonName: object["common_name"]?.string?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines),
                    confidenceScore: score, distinguishingFeature: object["distinguishing_feature"]?.string)
            }
        } else { candidates = nil }
        return SpeciesData(scanId: text("scan_id"), commonName: common, scientificName: scientific,
            insightData: .init(aiReasoning: insight?["ai_reasoning"]?.string ?? "", hazardType: insight?["hazard_type"]?.string ?? "none"),
            confidenceScore: confidence, blurScore: number("blur_score"),
            wikipediaUrl: text("wikipedia_url"), wikipediaOverview: text("wikipedia_overview"), referenceImageUrl: text("reference_image_url"),
            isBiological: biological, isLiveCapture: live, isInvasive: fields["is_invasive"]?.boolean ?? false,
            invasiveStatusRegion: text("invasive_status_region"), invasiveRationale: text("invasive_rationale"),
            invasiveConfidence: number("invasive_confidence"), ecologyType: text("ecology_type") ?? "unknown",
            taxonomy: .init(kingdom: taxonomy?["kingdom"]?.string, phylum: taxonomy?["phylum"]?.string,
                className: taxonomy?["class"]?.string, order: taxonomy?["order"]?.string,
                family: taxonomy?["family"]?.string, genus: taxonomy?["genus"]?.string),
            colors: strings("colors"), groupTags: strings("group_tags"), iucnRedListStatus: text("iucn_red_list_status"),
            estimatedSizeCm: number("estimated_size_cm"), lifeStage: text("life_stage"),
            reproductiveCondition: text("reproductive_condition"), sex: text("sex"), sexConfidence: number("sex_confidence"),
            sexEvidence: text("sex_evidence"), individualCount: integer("individual_count"), ecologicalInteractions: strings("ecological_interactions"),
            aiReasoning: text("ai_reasoning"), habitatDescription: fields["species_insights"]?.object?["habitat_description"]?.string,
            gbifTaxonKey: integer("gbif_taxon_key"), inferenceTier: text("inference_tier"), identificationProvenance: provenance,
            primaryIdentification: primary, alternativeCommonNames: strings("alternative_common_names"), petIdentification: pet,
            candidates: candidates, imageQualityScore: fields["image_quality"]?.object?["overall_score"]?.integer.flatMap(Int.init(exactly:)))
    }

}
