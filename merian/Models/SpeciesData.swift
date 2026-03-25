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
    var zoomFactor: CGFloat? = nil
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
            timestamp: DateUtilities.iso8601Formatter.string(from: Date())
        )
    }

    init(from context: EnvironmentContext, distance: Float?, zoom: CGFloat? = nil) {
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
            timestamp: DateUtilities.iso8601Formatter.string(from: context.location?.timestamp ?? Date())
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
    let diagnosticComparison: DiagnosticComparison?
    var wikipediaUrl: String?
    var wikipediaExtract: String?
    var referenceImageUrl: String?

    let isBiological: Bool
    let isLiveCapture: Bool
    let isInvasive: Bool
    let ecologyType: String
    let taxonomy: TaxonomyData?
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
            description: edgeRes.insight_data?.description ?? "No ecological description available for this subject.",
            isPoisonous: edgeRes.insight_data?.is_poisonous ?? false,
            regionalStatusRationale: edgeRes.insight_data?.regional_status_rationale
        )

        let taxonomyData = TaxonomyData(
            kingdom: edgeRes.taxonomy?.kingdom,
            phylum: edgeRes.taxonomy?.phylum,
            className: edgeRes.taxonomy?.class,
            order: edgeRes.taxonomy?.order,
            family: edgeRes.taxonomy?.family,
            genus: edgeRes.taxonomy?.genus
        )

        var parsedDiagnostic: DiagnosticComparison?
        if let diag = edgeRes.diagnostic_comparison,
           let rationale = diag.primary_match_rationale,
           let lookalike = diag.confusing_lookalike_name,
           let diffs = diag.key_differentiators,
           !diffs.isEmpty {
            parsedDiagnostic = DiagnosticComparison(
                primaryMatchRationale: rationale,
                confusingLookalikeName: lookalike,
                keyDifferentiators: diffs
            )
        }

        self.scanId = edgeRes.scan_id
        self.commonName = edgeRes.common_name ?? "Unknown Subject"
        self.scientificName = edgeRes.scientific_name ?? "Taxonomy Unavailable"
        self.insightData = insight
        self.confidenceScore = edgeRes.confidence_score ?? 0.0
        self.diagnosticComparison = parsedDiagnostic
        self.wikipediaUrl = edgeRes.wikipedia_url
        self.wikipediaExtract = edgeRes.wikipedia_extract
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
        diagnosticComparison: DiagnosticComparison? = nil,
        wikipediaUrl: String? = nil,
        wikipediaExtract: String? = nil,
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
        zoomFactor: Double? = nil
    ) {
        self.scanId = scanId
        self.commonName = commonName
        self.scientificName = scientificName
        self.insightData = insightData
        self.confidenceScore = confidenceScore
        self.diagnosticComparison = diagnosticComparison
        self.wikipediaUrl = wikipediaUrl
        self.wikipediaExtract = wikipediaExtract
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
    let description: String
    let isPoisonous: Bool
    let regionalStatusRationale: String?
}

struct DiagnosticComparison {
    let primaryMatchRationale: String
    let confusingLookalikeName: String
    let keyDifferentiators: [String]
}
