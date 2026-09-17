import Foundation

extension SpeciesData {
    /// Initializes from an `EdgeResponse` returned by the AI edge function.
    init(
        fromEdgeResponse edgeResponse: EdgeResponse,
        locationName: String?,
        weatherCondition: String?,
        weatherTemperatureF: Double?,
        gpsElevation: Double? = nil,
        gpsLatitude: Double? = nil,
        gpsLongitude: Double? = nil
    ) {
        let insight = InsightData(
            aiReasoning: edgeResponse.insight_data?.ai_reasoning ?? "",
            hazardType: edgeResponse.insight_data?.hazard_type ?? "none"
        )

        let taxonomyData = TaxonomyData(
            kingdom: edgeResponse.taxonomy?.kingdom,
            phylum: edgeResponse.taxonomy?.phylum,
            className: edgeResponse.taxonomy?.class,
            order: edgeResponse.taxonomy?.order,
            family: edgeResponse.taxonomy?.family,
            genus: edgeResponse.taxonomy?.genus
        )

        self.scanId = edgeResponse.scan_id
        self.presentationRole = .inferenceResult

        let primaryRawNames = edgeResponse.common_name?.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let mappedCommonName = primaryRawNames?.first ?? "Unknown Subject"
        let mappedScientificName = edgeResponse.scientific_name ?? "Taxonomy Unavailable"
        let mappedIsBiological = edgeResponse.is_biological_subject ?? true
        let mappedIsHuman = HumanSubjectIdentityPolicy.matches(
            commonName: mappedCommonName,
            scientificNames: [mappedScientificName]
        )
        let mappedHasResolvedTaxon = mappedIsBiological &&
            SpeciesIdentificationResolutionPolicy.isResolved(mappedScientificName) &&
            SpeciesIdentificationResolutionPolicy.isResolved(mappedCommonName)

        self.commonName = mappedCommonName
        self.scientificName = mappedScientificName
        self.insightData = insight
        self.confidenceScore = edgeResponse.confidence_score ?? 0.0
        self.blurScore = edgeResponse.blur_score
        self.similarSpecies = nil // populated asynchronously by enrich-scan
        self.wikipediaUrl = edgeResponse.wikipedia_url
        self.wikipediaOverview = edgeResponse.wikipedia_overview
        self.referenceImageUrl = ExternalReferenceImagePolicy.sanitizedURLList(
            edgeResponse.reference_image_url
        )
        self.isBiological = mappedIsBiological
        self.isLiveCapture = edgeResponse.is_live_capture ?? true
        self.isInvasive = edgeResponse.is_invasive ?? false
        self.invasiveStatusRegion = edgeResponse.invasive_status_region
        self.invasiveRationale = edgeResponse.invasive_rationale
        self.invasiveConfidence = edgeResponse.invasive_confidence
        self.ecologyType = edgeResponse.ecology_type ?? "unknown"
        self.taxonomy = taxonomyData
        self.isNewToMerianDictionary = mappedHasResolvedTaxon
            ? (edgeResponse.is_new_to_merian_dictionary ?? false)
            : false
        self.locationName = locationName
        self.weatherCondition = weatherCondition
        self.weatherTemperatureF = weatherTemperatureF
        self.gpsElevation = gpsElevation
        self.gpsLatitude = gpsLatitude
        self.gpsLongitude = gpsLongitude
        self.colors = edgeResponse.colors
        self.groupTags = edgeResponse.group_tags
        self.iucnRedListStatus = edgeResponse.iucn_red_list_status
        self.zoomFactor = nil // populated by the caller from CaptureTelemetry
        self.estimatedSizeCm = edgeResponse.estimated_size_cm
        self.lifeStage = edgeResponse.life_stage
        self.reproductiveCondition = edgeResponse.reproductive_condition
        self.sex = edgeResponse.sex
        self.sexConfidence = edgeResponse.sex_confidence
        self.sexEvidence = edgeResponse.sex_evidence
        self.individualCount = edgeResponse.individual_count
        self.ecologicalInteractions = edgeResponse.ecological_interactions
        self.aiReasoning = edgeResponse.insight_data?.ai_reasoning // scan-specific evidence
        self.habitatDescription = edgeResponse.species_insights?
            .habitat_description?
            .trimmedNonEmptyValue
        self.gbifTaxonKey = edgeResponse.gbif_taxon_key
        self.inferenceTier = edgeResponse.inference_tier
        self.alternativeCommonNames = SpeciesData.sanitizeAlternativeNames(
            edgeResponse.alternative_common_names
        )
        if mappedHasResolvedTaxon,
           !mappedIsHuman,
           let petDTO = edgeResponse.pet_identification {
            let petIdentification = PetIdentification(
                speciesGroup: petDTO.speciesGroup,
                label: petDTO.label,
                labelType: petDTO.labelType,
                confidenceScore: petDTO.confidenceScore,
                evidence: petDTO.evidence
            )
            self.petIdentification = petIdentification.isDisplayable
                ? petIdentification
                : nil
        } else {
            self.petIdentification = nil
        }
        self.candidates = mappedHasResolvedTaxon && !mappedIsHuman
            ? edgeResponse.candidates.map { entries in
                entries.map { entry in
                    let commonName = entry.common_name?
                        .components(separatedBy: ",")
                        .first?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return IdentificationCandidate(
                        scientificName: entry.scientific_name,
                        commonName: commonName,
                        confidenceScore: entry.confidence_score,
                        distinguishingFeature: entry.distinguishing_feature
                    )
                }
            }
            : nil
        self.imageQualityScore = edgeResponse.image_quality?.overall_score
        self.aiScientificName = mappedScientificName
        self.userIdentificationOverride = nil
        self.userConfirmedIdentification = false
        self.isFlagged = false
        self.alternativesExhausted = false
        self.audioFilePaths = nil // populated by inference processing
        self.videoFilePaths = nil
    }
}
