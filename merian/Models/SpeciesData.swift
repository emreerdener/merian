import Foundation

// MARK: - Primary Domain Models (Data received from InferenceEngine/Gemini Edge JSON)
struct SpeciesData {
    let scanId: String?
    let commonName: String
    let scientificName: String
    let insightData: InsightData
    let confidenceScore: Double
    let diagnosticComparison: DiagnosticComparison?
    let wikipediaUrl: String?
    let wikipediaExtract: String?
    let referenceImageUrl: String?
    
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
}

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
    let keyDifferentiators: [KeyDifferentiator]
}

struct KeyDifferentiator: Identifiable {
    let id = UUID()
    let trait: String
    let subjectValue: String
    let lookalikeValue: String
}
