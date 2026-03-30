import Foundation

// MARK: - Capture Telemetry

/// Sensor and environment state captured at the moment of shutter press.
/// Passed to both the live inference path and the offline queue.
struct CaptureTelemetry: Sendable {
    let subjectDistanceInMeters: Float?
    let gpsLatitude: Double?
    let gpsLongitude: Double?
    let gpsElevation: Double?
    let locationName: String?
    let weatherCondition: String?
    let weatherTemperatureF: Double?
    let timeOfDay: String?
    let timestamp: String?
    /// Active zoom factor at shutter press. Nil when 1× (adds no signal).
    /// Omitted from offline-queue retries since zoom is not persisted in the schema.
    var zoomFactor: CGFloat?
    var estimatedSizeCm: Double?
}

// MARK: - Convenience Initializers

extension CaptureTelemetry {
    @MainActor
    init(from inferenceEngine: InferenceEngine) {
        self.init(
            subjectDistanceInMeters: inferenceEngine.activeDistanceInMeters,
            gpsLatitude: inferenceEngine.activeLatitude,
            gpsLongitude: inferenceEngine.activeLongitude,
            gpsElevation: inferenceEngine.activeElevation,
            locationName: inferenceEngine.activeLocationName,
            weatherCondition: inferenceEngine.activeWeatherCondition,
            weatherTemperatureF: inferenceEngine.activeTemperatureF,
            timeOfDay: nil,
            timestamp: DateUtilities.iso8601Formatter.string(from: Date()),
            estimatedSizeCm: nil
        )
    }

    init(from context: EnvironmentContext, distance: Float?, zoom: CGFloat? = nil, estimatedSizeCm: Double? = nil) {
        let reliableElevation: Double? = context.location.flatMap { loc in
            (loc.verticalAccuracy >= 0 && loc.verticalAccuracy <= 25) ? loc.altitude : nil
        }

        var t = CaptureTelemetry(
            subjectDistanceInMeters: distance,
            gpsLatitude: context.location?.coordinate.latitude,
            gpsLongitude: context.location?.coordinate.longitude,
            gpsElevation: reliableElevation,
            locationName: context.locationName,
            weatherCondition: context.weatherCondition,
            weatherTemperatureF: context.weatherTemperature,
            timeOfDay: nil,
            timestamp: DateUtilities.iso8601Formatter.string(from: context.captureDate ?? context.location?.timestamp ?? Date()),
            estimatedSizeCm: estimatedSizeCm
        )
        t.zoomFactor = zoom
        self = t
    }
}

// MARK: - Species Data

/// Parsed result from the AI edge function, representing a single identified biological observation.
struct SpeciesData {
    let scanId: String?
    let commonName: String
    let scientificName: String
    let insightData: InsightData
    let confidenceScore: Double
    /// Gemini's self-reported image sharpness score (0 = sharp, 1 = very blurry).
    /// Populated from live inference only — nil when loading from local SwiftData records.
    let blurScore: Double?
    var similarSpecies: SimilarSpecies?
    var wikipediaUrl: String?
    /// Wikipedia summary paragraph cached from the Wikipedia REST API.
    var wikipediaOverview: String?
    var referenceImageUrl: String?

    let isBiological: Bool
    let isLiveCapture: Bool
    let isInvasive: Bool
    let ecologyType: String
    var taxonomy: TaxonomyData?
    var isNewDiscovery: Bool = false

    // Context metadata from the scan session.
    var locationName: String?
    var weatherCondition: String?
    var weatherTemperatureF: Double?
    var gpsElevation: Double?
    var gpsLatitude: Double?
    var gpsLongitude: Double?
    var colors: [String]?
    var groupTags: [String]?
    let iucnRedListStatus: String?
    var zoomFactor: Double?
    
    // Extended Ecological Telemetry
    var estimatedSizeCm: Double?
    var lifeStage: String?
    var reproductiveCondition: String?
    var individualCount: Int?
    var ecologicalInteractions: [String]?

    // Species Insights
    var aiReasoning: String?
    var habitatDescription: String?
    var gbifTaxonKey: Int?
    var inferenceTier: String?
}

// MARK: - Edge Response Init

extension SpeciesData {
    /// Initializes from an `EdgeResponse` returned by the AI edge function.
    init(
        fromEdgeResponse edgeRes: EdgeResponse,
        locationName: String?,
        weatherCondition: String?,
        weatherTemperatureF: Double?,
        gpsElevation: Double? = nil,
        gpsLatitude: Double? = nil,
        gpsLongitude: Double? = nil
    ) {
        let insight = InsightData(
            aiReasoning: edgeRes.insight_data?.ai_reasoning ?? "No ecological description available for this subject.",
            hazardType: edgeRes.insight_data?.hazard_type ?? "none"
        )

        let taxonomyData = TaxonomyData(
            kingdom: edgeRes.taxonomy?.kingdom,
            phylum: edgeRes.taxonomy?.phylum,
            className: edgeRes.taxonomy?.class,
            order: edgeRes.taxonomy?.order,
            family: edgeRes.taxonomy?.family,
            genus: edgeRes.taxonomy?.genus
        )

        self.scanId = edgeRes.scan_id
        self.commonName = edgeRes.common_name ?? "Unknown Subject"
        self.scientificName = edgeRes.scientific_name ?? "Taxonomy Unavailable"
        self.insightData = insight
        self.confidenceScore = edgeRes.confidence_score ?? 0.0
        self.blurScore = edgeRes.blur_score
        self.similarSpecies = nil  // populated async via enrich-scan
        self.wikipediaUrl = edgeRes.wikipedia_url
        self.wikipediaOverview = edgeRes.wikipedia_overview
        self.referenceImageUrl = edgeRes.reference_image_url
        self.isBiological = edgeRes.is_biological_subject ?? true
        self.isLiveCapture = edgeRes.is_live_capture ?? true
        self.isInvasive = edgeRes.is_invasive ?? false
        self.ecologyType = edgeRes.ecology_type ?? "unknown"
        self.taxonomy = taxonomyData
        self.locationName = locationName
        self.weatherCondition = weatherCondition
        self.weatherTemperatureF = weatherTemperatureF
        self.gpsElevation = gpsElevation
        self.gpsLatitude = gpsLatitude
        self.gpsLongitude = gpsLongitude
        self.colors = edgeRes.colors
        self.groupTags = edgeRes.group_tags
        self.iucnRedListStatus = edgeRes.iucn_red_list_status
        self.zoomFactor = nil  // populated by the caller from CaptureTelemetry
        self.estimatedSizeCm = edgeRes.estimated_size_cm
        self.lifeStage = edgeRes.life_stage
        self.reproductiveCondition = edgeRes.reproductive_condition
        self.individualCount = edgeRes.individual_count
        self.ecologicalInteractions = edgeRes.ecological_interactions
        self.aiReasoning = edgeRes.insight_data?.ai_reasoning  // per-scan; unique to the specific photo submitted
        self.habitatDescription = edgeRes.species_insights?.habitat_description
        self.gbifTaxonKey = edgeRes.gbif_taxon_key
        self.inferenceTier = edgeRes.inference_tier
    }
}

// MARK: - Memberwise Init

extension SpeciesData {
    /// Full memberwise initializer, used for local construction and offline mocking.
    init(
        scanId: String? = nil,
        commonName: String,
        scientificName: String,
        insightData: InsightData,
        confidenceScore: Double,
        blurScore: Double? = nil,
        similarSpecies: SimilarSpecies? = nil,
        wikipediaUrl: String? = nil,
        wikipediaOverview: String? = nil,
        referenceImageUrl: String? = nil,
        isBiological: Bool = true,
        isLiveCapture: Bool = true,
        isInvasive: Bool = false,
        ecologyType: String = "unknown",
        taxonomy: TaxonomyData? = nil,
        locationName: String? = nil,
        weatherCondition: String? = nil,
        weatherTemperatureF: Double? = nil,
        gpsElevation: Double? = nil,
        gpsLatitude: Double? = nil,
        gpsLongitude: Double? = nil,
        colors: [String]? = nil,
        groupTags: [String]? = nil,
        iucnRedListStatus: String? = nil,
        zoomFactor: Double? = nil,
        estimatedSizeCm: Double? = nil,
        lifeStage: String? = nil,
        reproductiveCondition: String? = nil,
        individualCount: Int? = nil,
        ecologicalInteractions: [String]? = nil,
        aiReasoning: String? = nil,
        habitatDescription: String? = nil,
        gbifTaxonKey: Int? = nil,
        inferenceTier: String? = nil
    ) {
        self.scanId = scanId
        self.commonName = commonName
        self.scientificName = scientificName
        self.insightData = insightData
        self.confidenceScore = confidenceScore
        self.blurScore = blurScore
        self.similarSpecies = similarSpecies
        self.wikipediaUrl = wikipediaUrl
        self.wikipediaOverview = wikipediaOverview
        self.referenceImageUrl = referenceImageUrl
        self.isBiological = isBiological
        self.isLiveCapture = isLiveCapture
        self.isInvasive = isInvasive
        self.ecologyType = ecologyType
        self.taxonomy = taxonomy
        self.locationName = locationName
        self.weatherCondition = weatherCondition
        self.weatherTemperatureF = weatherTemperatureF
        self.gpsElevation = gpsElevation
        self.gpsLatitude = gpsLatitude
        self.gpsLongitude = gpsLongitude
        self.colors = colors
        self.groupTags = groupTags
        self.iucnRedListStatus = iucnRedListStatus
        self.zoomFactor = zoomFactor
        self.estimatedSizeCm = estimatedSizeCm
        self.lifeStage = lifeStage
        self.reproductiveCondition = reproductiveCondition
        self.individualCount = individualCount
        self.ecologicalInteractions = ecologicalInteractions
        self.aiReasoning = aiReasoning
        self.habitatDescription = habitatDescription
        self.gbifTaxonKey = gbifTaxonKey
        self.inferenceTier = inferenceTier
    }
}

// MARK: - Supporting Types

struct TaxonomyData {
    let kingdom: String?
    let phylum: String?
    let className: String?
    let order: String?
    let family: String?
    let genus: String?
}

struct InsightData {
    /// Per-scan AI vision reasoning — unique to the specific photo submitted.
    let aiReasoning: String
    /// AI-classified hazard type. One of: `"none"` | `"poisonous"` | `"venomous"` | `"allergenic"` | `"irritant"`.
    let hazardType: String
    var isHazardous: Bool { hazardType != "none" }
}

struct SimilarSpeciesEntry {
    let scientificName: String
    let commonName: String?
    let referenceImageUrl: String?
    let iucnRedListStatus: String?
}

struct SimilarSpecies {
    let entries: [SimilarSpeciesEntry]

    /// Backwards-compatible accessor returning the flat array of scientific names.
    var lookalikes: [String] { entries.map(\.scientificName) }
}
