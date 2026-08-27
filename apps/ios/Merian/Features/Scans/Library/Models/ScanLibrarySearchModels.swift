import Foundation

/// A value-only mirror used to build the search index away from SwiftData's actor.
struct RawScanSnapshot: Sendable {
    let id: String
    let commonName: String
    let scientificName: String
    let petLabel: String?
    let ecologyType: String
    let semanticTags: [String]
    let customTags: [String]
    let isInvasive: Bool
    let taxonomyKingdom: String?
    let taxonomyClass: String?
    let taxonomyOrder: String?
    let taxonomyFamily: String?
    let aiReasoning: String?
    let locationName: String?
    let habitatDescription: String?
    let weatherCondition: String?
    let lifeStage: String?
    let reproductiveCondition: String?
    let sex: String?
    let sexEvidence: String?
    let similarSpecies: [String]?
    let iucnRedListStatus: String?
    let hazardType: String
    let ecologicalInteractions: [String]?

    @MainActor
    init(record: LocalScanRecord) {
        id = record.id
        commonName = record.commonName
        scientificName = record.scientificName
        petLabel = record.petIdentification?.label
        ecologyType = record.ecologyType
        semanticTags = record.semanticTags
        customTags = record.customTags
        isInvasive = record.isInvasive
        taxonomyKingdom = record.taxonomyKingdom
        taxonomyClass = record.taxonomyClass
        taxonomyOrder = record.taxonomyOrder
        taxonomyFamily = record.taxonomyFamily
        aiReasoning = record.aiReasoning
        locationName = record.locationName
        habitatDescription = record.habitatDescription
        weatherCondition = record.weatherCondition
        lifeStage = record.lifeStage
        reproductiveCondition = record.reproductiveCondition
        sex = record.sex
        sexEvidence = record.sexEvidence
        similarSpecies = record.similarSpecies
        iucnRedListStatus = record.iucnRedListStatus
        hazardType = record.hazardType
        ecologicalInteractions = record.ecologicalInteractions
    }
}

struct ScanSortPrimitive: Sendable {
    let id: String
    let timestamp: Date
    let commonName: String
}

enum ScanLibrarySortPolicy {
    nonisolated static func sort(
        _ subset: [ScanSortPrimitive],
        by option: ScanSortOption
    ) -> [ScanSortPrimitive] {
        switch option {
        case .newest:
            subset.sorted { $0.timestamp > $1.timestamp }
        case .oldest:
            subset.sorted { $0.timestamp < $1.timestamp }
        case .aToZ:
            subset.sorted {
                $0.commonName.localizedCaseInsensitiveCompare($1.commonName) == .orderedAscending
            }
        case .zToA:
            subset.sorted {
                $0.commonName.localizedCaseInsensitiveCompare($1.commonName) == .orderedDescending
            }
        }
    }
}

#if DEBUG
enum ScansLibrarySearchDebugEvent: Equatable {
    case indexingCompleted(documentCount: Int)
    case filterIndexingCompleted(documentCount: Int)
    case searchCompleted(query: String, resultCount: Int)
}
#endif
