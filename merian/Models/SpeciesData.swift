import Foundation

// MARK: - Sensor Telemetry Context
/// Encapsulates the complete global physical context at the exact moment of shutter press.
/// Consolidates 13 separate sensory parameters cleanly mapping directly across Offline Queue, Core AI loop, and Merian's backend boundary flawlessly!
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
}

// MARK: - Telemetry DRY Injectors
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
    
    init(from context: EnvironmentContext, distance: Float?) {
        var reliableElevation: Double? = nil
        if let location = context.location, location.verticalAccuracy >= 0 && location.verticalAccuracy <= 25 {
            reliableElevation = location.altitude
        }
        
        self.init(
            subjectDistanceInMeters: distance,
            gpsLatitude: context.location?.coordinate.latitude,
            gpsLongitude: context.location?.coordinate.longitude,
            gpsElevation: reliableElevation,
            locationName: context.locationName,
            weatherCondition: context.weatherCondition,
            weatherTemperatureF: context.weatherTemperature,
            timeOfDay: nil,
            timestamp: ISO8601DateFormatter().string(from: context.location?.timestamp ?? Date())
        )
    }
}

// MARK: - Primary AI Knowledge Domain
/// Defines the explicit parsed biological constraints mapped natively from the Gemini Edge JSON Engine.
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
    
    // UI Metadata for Historical Insight Sheet contextual binding
    var locationName: String?
    var weatherCondition: String?
    var weatherTemperatureF: Double?
    var gpsElevation: Double?
    var gpsLatitude: Double?
    var gpsLongitude: Double?
    var colors: [String]?
    let iucnRedListStatus: String?
    
    // MARK: - JSON Decoding Deserializer
    /// DRY Architectural Decoding Strategy Context explicitly mapping standard dictionaries natively to struct bounds securely
    init(fromEdgeResponse edgeRes: InferenceEngine.EdgeResponse, locationName: String?, weatherCondition: String?, weatherTemperatureF: Double?, gpsElevation: Double? = nil, gpsLatitude: Double? = nil, gpsLongitude: Double? = nil) {
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
        
        var parsedDiagnostic: DiagnosticComparison? = nil
        if let diag = edgeRes.diagnostic_comparison,
           let rationale = diag.primary_match_rationale,
           let lookalike = diag.confusing_lookalike_name,
           let diffs = diag.key_differentiators,
           !diffs.isEmpty {
            parsedDiagnostic = DiagnosticComparison(primaryMatchRationale: rationale, confusingLookalikeName: lookalike, keyDifferentiators: diffs)
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
        self.iucnRedListStatus = edgeRes.iucn_red_list_status
    }
    
    // MARK: - Manual Struct Injectors
    /// Explicit Memberwise Initialization for Fallbacks and Offline Mocking explicitly bypassing standard Decoding bounds seamlessly
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
        iucnRedListStatus: String? = nil
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
        self.iucnRedListStatus = iucnRedListStatus
    }
}

// MARK: - Biological Taxonomies
struct TaxonomyData {
    let kingdom: String?
    let phylum: String?
    let className: String?
    let order: String?
    let family: String?
    let genus: String?
}

// MARK: - Ecological Insights
struct InsightData {
    let description: String
    let isPoisonous: Bool
    let regionalStatusRationale: String?
}

// MARK: - Analytical Diagnostics
struct DiagnosticComparison {
    let primaryMatchRationale: String
    let confusingLookalikeName: String
    let keyDifferentiators: [String]
}
