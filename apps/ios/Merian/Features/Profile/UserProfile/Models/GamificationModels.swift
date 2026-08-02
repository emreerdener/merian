import Foundation
import SwiftUI

enum AchievementType: String, CaseIterable, Sendable, Identifiable {
    case firstScan = "first_scan"
    case firstFieldTrip = "first_field_trip"
    case explorer = "explorer"
    case plantae = "plantae"
    case insecta = "insecta"
    case fungi = "fungi"
    case urban = "urban"
    case domesticCat = "domestic_cat"
    case domesticDog = "domestic_dog"
    case frostWalker = "frost_walker"
    case alpine = "alpine"
    case nocturnal = "nocturnal"
    case guardian = "guardian"
    case conservationist = "conservationist"
    case toxicologist = "toxicologist"
    case perfectLens = "perfect_lens"

    var id: String { rawValue }

    var definition: AchievementDefinition {
        switch self {
        case .firstScan:
            return AchievementDefinition(
                title: "The Observer",
                targetCount: 1,
                descriptionText: "Complete your first nature scan",
                detailProgressDescription: "Your first successful scan unlocks this achievement.",
                qualifyingScansTitle: "Unlocking scan",
                imageName: "chick",
                tintToken: .springGreen,
                difficultyLevel: 0,
                contributionKind: .firstScan(reasonText: "Your first recorded scan")
            )
        case .firstFieldTrip:
            return AchievementDefinition(
                title: "The Field Naturalist",
                targetCount: 1,
                descriptionText: "Complete your first Field trip",
                detailProgressDescription: "Your first completed Field trip unlocks this achievement.",
                qualifyingScansTitle: "Unlock requirement",
                imageName: "boots",
                tintToken: .terracotta,
                difficultyLevel: 0,
                contributionKind: .externalMilestone
            )
        case .explorer:
            return AchievementDefinition(
                title: "The Naturalist",
                targetCount: 5,
                descriptionText: "Document 5 different species",
                detailProgressDescription: "Each unique species counts once toward this achievement.",
                qualifyingScansTitle: "Qualifying scans",
                imageName: "leaf-feather",
                tintToken: .ochre,
                difficultyLevel: 0,
                contributionKind: .uniqueSpecies { _ in
                    "Unique species documented"
                }
            )
        case .plantae:
            return AchievementDefinition(
                title: "The Botanist",
                targetCount: 10,
                descriptionText: "Document 10 different plant species",
                detailProgressDescription: "Each unique plant species counts once toward this achievement.",
                qualifyingScansTitle: "Qualifying scans",
                imageName: "leaves",
                tintToken: .forest,
                difficultyLevel: 0,
                contributionKind: .uniqueSpecies { record in
                    guard record.taxonomyKingdom?.trimmedLowercased == "plantae" else { return nil }
                    return "Plant kingdom"
                }
            )
        case .insecta:
            return AchievementDefinition(
                title: "The Zoologist",
                targetCount: 10,
                descriptionText: "Document 10 different insect or arachnid species",
                detailProgressDescription: "Each unique insect or arachnid species counts once toward this achievement.",
                qualifyingScansTitle: "Qualifying scans",
                imageName: "zoo-scene",
                tintToken: .terracotta,
                difficultyLevel: 1,
                contributionKind: .uniqueSpecies { record in
                    guard let className = record.taxonomyClass?.trimmedLowercased,
                          className == "insecta" || className == "arachnida" else { return nil }
                    return className == "arachnida" ? "Arachnida class" : "Insecta class"
                }
            )
        case .fungi:
            return AchievementDefinition(
                title: "The Mycologist",
                targetCount: 10,
                descriptionText: "Document 10 different fungi species",
                detailProgressDescription: "Each unique fungi species counts once toward this achievement.",
                qualifyingScansTitle: "Qualifying scans",
                imageName: "mushroom",
                tintToken: .mauve,
                difficultyLevel: 2,
                contributionKind: .uniqueSpecies { record in
                    guard record.taxonomyKingdom?.trimmedLowercased == "fungi" else { return nil }
                    return "Fungi kingdom"
                }
            )
        case .urban:
            return AchievementDefinition(
                title: "The Urban Ecologist",
                targetCount: 10,
                descriptionText: "Document 10 species in urban or domesticated environments",
                detailProgressDescription: "Each unique species captured in an urban or domesticated environment counts once.",
                qualifyingScansTitle: "Qualifying scans",
                imageName: "urban-building",
                tintToken: .slateBlue,
                difficultyLevel: 0,
                contributionKind: .uniqueSpecies { record in
                    let ecology = record.ecologyType.trimmedLowercased
                    guard ecology == "urban" || ecology == "domesticated" else { return nil }
                    return "Urban or domesticated environment"
                }
            )
        case .domesticCat:
            return AchievementDefinition(
                title: "The Feline Friend",
                targetCount: 1,
                descriptionText: "Scan a domestic cat",
                detailProgressDescription: "Your first domestic cat scan unlocks this achievement.",
                qualifyingScansTitle: "Latest qualifying scan",
                imageName: "cat",
                tintToken: .mauve,
                difficultyLevel: 0,
                contributionKind: .uniqueSpecies { record in
                    DomesticPetAchievementMatcher.catReason(for: record)
                }
            )
        case .domesticDog:
            return AchievementDefinition(
                title: "The Canine Companion",
                targetCount: 1,
                descriptionText: "Scan a domestic dog",
                detailProgressDescription: "Your first domestic dog scan unlocks this achievement.",
                qualifyingScansTitle: "Latest qualifying scan",
                imageName: "dog",
                tintToken: .ochre,
                difficultyLevel: 0,
                contributionKind: .uniqueSpecies { record in
                    DomesticPetAchievementMatcher.dogReason(for: record)
                }
            )
        case .frostWalker:
            return AchievementDefinition(
                title: "The Frost Walker",
                targetCount: 5,
                descriptionText: "Document 5 species in freezing temperatures",
                detailProgressDescription: "Each unique species captured below 32 degrees Fahrenheit counts once.",
                qualifyingScansTitle: "Qualifying scans",
                imageName: "snowflake",
                tintToken: .sky,
                difficultyLevel: 2,
                contributionKind: .uniqueSpecies { record in
                    guard let temperature = record.weatherTemperatureF, temperature < 32.0 else { return nil }
                    return "\(Int(temperature.rounded())) degrees Fahrenheit"
                }
            )
        case .alpine:
            return AchievementDefinition(
                title: "The Alpine Naturalist",
                targetCount: 5,
                descriptionText: "Document 5 species above 2,500 meters",
                detailProgressDescription: "Each unique species captured above 2,500 meters counts once.",
                qualifyingScansTitle: "Qualifying scans",
                imageName: "mountain",
                tintToken: .mist,
                difficultyLevel: 2,
                contributionKind: .uniqueSpecies { record in
                    guard let elevation = record.gpsElevation, elevation > 2500.0 else { return nil }
                    return "\(Int(elevation.rounded())) meter elevation"
                }
            )
        case .nocturnal:
            return AchievementDefinition(
                title: "The Nocturnal Observer",
                targetCount: 10,
                descriptionText: "Document 10 species after dark",
                detailProgressDescription: "Each unique species captured between 10 PM and 5 AM counts once.",
                qualifyingScansTitle: "Qualifying scans",
                imageName: "moon",
                tintToken: .night,
                difficultyLevel: 1,
                contributionKind: .uniqueSpecies { record in
                    let hour = Calendar.current.component(.hour, from: record.observationDate)
                    guard hour >= 22 || hour <= 5 else { return nil }
                    return "Captured after dark"
                }
            )
        case .guardian:
            return AchievementDefinition(
                title: "The Guardian",
                targetCount: 5,
                descriptionText: "Identify 5 known invasive species",
                detailProgressDescription: "Each unique invasive species counts once toward this achievement.",
                qualifyingScansTitle: "Qualifying scans",
                imageName: "ivy",
                tintToken: .crimson,
                difficultyLevel: 1,
                contributionKind: .uniqueSpecies { record in
                    guard record.isInvasive else { return nil }
                    return "Marked invasive"
                }
            )
        case .conservationist:
            return AchievementDefinition(
                title: "The Conservationist",
                targetCount: 1,
                descriptionText: "Document an at-risk species on the IUCN Red List",
                detailProgressDescription: "Each unique at-risk species counts once toward this achievement.",
                qualifyingScansTitle: "Qualifying scans",
                imageName: "shield",
                tintToken: .teal,
                difficultyLevel: 2,
                contributionKind: .uniqueSpecies { record in
                    guard let status = record.iucnRedListStatus?.trimmedUppercased,
                          !status.isEmpty,
                          status != "LC",
                          status != "NE",
                          status != "DD" else { return nil }
                    return "IUCN \(status)"
                }
            )
        case .toxicologist:
            return AchievementDefinition(
                title: "The Toxicologist",
                targetCount: 5,
                descriptionText: "Document 5 species flagged as hazardous",
                detailProgressDescription: "Each unique species flagged as hazardous counts once toward this achievement.",
                qualifyingScansTitle: "Qualifying scans",
                imageName: "toxic",
                tintToken: .acid,
                difficultyLevel: 1,
                contributionKind: .uniqueSpecies { record in
                    let hazardType = record.hazardType.trimmedLowercased
                    guard hazardType != "none", !hazardType.isEmpty else { return nil }
                    return hazardType
                        .replacingOccurrences(of: "_", with: " ")
                        .capitalized
                }
            )
        case .perfectLens:
            return AchievementDefinition(
                title: "The Perfect Lens",
                targetCount: 25,
                descriptionText: "Document 25 species with 98%+ AI confidence",
                detailProgressDescription: "Each unique species with a 98 percent or higher confidence capture counts once.",
                qualifyingScansTitle: "Qualifying scans",
                imageName: "camera-lens",
                tintToken: .azure,
                difficultyLevel: 1,
                contributionKind: .uniqueSpecies { record in
                    guard let score = record.confidenceScore, score >= 0.98 else { return nil }
                    return "\(Int((score * 100).rounded())) percent AI confidence"
                }
            )
        }
    }
}

protocol AchievementRecordRepresentable {
    var id: String { get }
    var speciesId: String { get }
    var scientificName: String { get }
    var userIdentificationOverride: String? { get }
    var confirmedSpeciesId: String? { get }
    var timestamp: Date { get }
    var captureDate: Date? { get }
    var taxonomyKingdom: String? { get }
    var taxonomyClass: String? { get }
    var ecologyType: String { get }
    var weatherTemperatureF: Double? { get }
    var gpsElevation: Double? { get }
    var isBiological: Bool { get }
    var isInvasive: Bool { get }
    var iucnRedListStatus: String? { get }
    var hazardType: String { get }
    var confidenceScore: Double? { get }
    var commonName: String? { get }
    var locationName: String? { get }
    var imagePath: String? { get }
    var fallbackImageUrl: String? { get }
    var audioPath: String? { get }
    var placeholderStyle: ScanThumbnailPlaceholderStyle { get }
}

extension AchievementRecordRepresentable {
    var commonName: String? { nil }
    var locationName: String? { nil }
    var imagePath: String? { nil }
    var fallbackImageUrl: String? { nil }
    var audioPath: String? { nil }
    var placeholderStyle: ScanThumbnailPlaceholderStyle { .archived }

    var displayScientificName: String {
        trimmedNonEmpty(userIdentificationOverride) ?? scientificName
    }

    var observationDate: Date {
        captureDate ?? timestamp
    }

    var canonicalSpeciesKey: String {
        if let confirmedSpeciesId = trimmedNonEmpty(confirmedSpeciesId) {
            return "confirmed:\(confirmedSpeciesId)"
        }
        if let speciesId = trimmedNonEmpty(speciesId) {
            return "species:\(speciesId)"
        }
        return "scientific:\(displayScientificName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    var displayCommonName: String {
        trimmedNonEmpty(commonName) ?? displayScientificName
    }

    private func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }
}

struct AchievementDefinition: Sendable {
    let title: String
    let targetCount: Int
    let descriptionText: String
    let detailProgressDescription: String
    let qualifyingScansTitle: String
    let imageName: String
    let tintToken: AchievementTintToken
    let difficultyLevel: Int
    let contributionKind: AchievementContributionKind
}

enum AchievementContributionKind: Sendable {
    case firstScan(reasonText: String)
    case externalMilestone
    case uniqueSpecies(qualifyingReason: @Sendable (any AchievementRecordRepresentable) -> String?)
}

private enum DomesticPetAchievementMatcher {
    private static let domesticCatScientificNames: Set<String> = [
        "felis catus",
        "felis silvestris catus",
        "felis domesticus",
        "felis catus domesticus",
        "felis silvestris domesticus"
    ]

    private static let domesticDogScientificNames: Set<String> = [
        "canis lupus familiaris",
        "canis familiaris",
        "canis familiaris domesticus"
    ]

    static func catReason(for record: any AchievementRecordRepresentable) -> String? {
        guard domesticCatScientificNames.contains(record.displayScientificName.normalizedScientificName) else {
            return nil
        }
        return "Domestic cat"
    }

    static func dogReason(for record: any AchievementRecordRepresentable) -> String? {
        guard domesticDogScientificNames.contains(record.displayScientificName.normalizedScientificName) else {
            return nil
        }
        return "Domestic dog"
    }
}

enum AchievementTintToken: Sendable {
    case springGreen
    case ochre
    case forest
    case terracotta
    case mauve
    case slateBlue
    case sky
    case mist
    case night
    case crimson
    case teal
    case acid
    case azure

    var color: Color {
        switch self {
        case .springGreen: return Color(red: 0.25, green: 0.75, blue: 0.35)
        case .ochre: return Color(red: 0.8, green: 0.6, blue: 0.2)
        case .forest: return Color(red: 0.3, green: 0.6, blue: 0.3)
        case .terracotta: return Color(red: 0.8, green: 0.4, blue: 0.3)
        case .mauve: return Color(red: 0.6, green: 0.4, blue: 0.6)
        case .slateBlue: return Color(red: 0.4, green: 0.5, blue: 0.7)
        case .sky: return Color(red: 0.4, green: 0.7, blue: 0.9)
        case .mist: return Color(red: 0.6, green: 0.6, blue: 0.7)
        case .night: return Color(red: 0.3, green: 0.2, blue: 0.6)
        case .crimson: return Color(red: 0.85, green: 0.3, blue: 0.3)
        case .teal: return Color(red: 0.2, green: 0.6, blue: 0.5)
        case .acid: return Color(red: 0.75, green: 0.8, blue: 0.1)
        case .azure: return Color(red: 0.3, green: 0.5, blue: 0.9)
        }
    }
}

// MARK: - Gamification Payloads
struct AwardPayload: Sendable, Identifiable {
    let type: AchievementType
    let currentCount: Int
    let lastInteractionDate: Date?
    let unlockedAt: Date?
    let destination: CaptureGoalDestination?

    var id: String { type.id }

    init(
        type: AchievementType,
        currentCount: Int,
        lastInteractionDate: Date?,
        unlockedAt: Date? = nil,
        destination: CaptureGoalDestination? = nil
    ) {
        self.type = type
        self.currentCount = currentCount
        self.lastInteractionDate = lastInteractionDate
        self.unlockedAt = unlockedAt
        self.destination = destination
    }
}

struct AchievementContribution: Sendable, Identifiable, Equatable {
    let scanID: String
    let commonName: String
    let scientificName: String
    let timestamp: Date
    let reasonText: String
    let imagePath: String?
    let fallbackImageUrl: String?
    let audioPath: String?
    let placeholderStyle: ScanThumbnailPlaceholderStyle
    let locationName: String?

    var id: String { scanID }
}

struct AchievementDetailPayload: Sendable, Identifiable {
    let award: AwardPayload
    let contributions: [AchievementContribution]

    var id: String { award.id }
}

extension AwardPayload {
    var definition: AchievementDefinition {
        type.definition
    }

    var title: String {
        definition.title
    }

    var targetCount: Int {
        definition.targetCount
    }

    var descriptionText: String {
        definition.descriptionText
    }

    var detailProgressDescription: String {
        definition.detailProgressDescription
    }

    var qualifyingScansTitle: String {
        definition.qualifyingScansTitle
    }

    var difficultyLevel: Int {
        definition.difficultyLevel
    }

    var difficultyString: String {
        switch difficultyLevel {
        case 2: return "Hard"
        case 1: return "Medium"
        default: return "Easy"
        }
    }

    var isCompleted: Bool {
        currentCount >= targetCount
    }

    var progressFraction: Double {
        min(Double(currentCount) / Double(targetCount), 1.0)
    }

    var tintInfo: (color: Color, imageName: String) {
        (definition.tintToken.color, definition.imageName)
    }

    var accessibilityProgressSummary: String {
        "\(title). \(currentCount) of \(targetCount). \(progressStatusText). \(detailProgressDescription)"
    }

    var cardAccessibilityLabel: String {
        if isCompleted {
            return "\(title). Completed achievement. \(descriptionText)"
        }
        return "\(title). Progress \(currentCount) of \(targetCount). \(descriptionText)"
    }

    var cardAccessibilityHint: String {
        if isCompleted, destination != nil {
            return "Opens the Field trip that unlocked this achievement."
        }
        if type == .firstFieldTrip {
            return "Opens the achievement requirement."
        }
        return "Opens the achievement details and qualifying scans."
    }

    var progressStatusText: String {
        isCompleted ? "Completed" : "In progress"
    }
}

// MARK: - Sorting UI State
enum AwardSortOption: String, CaseIterable, Hashable, Identifiable {
    case smartSort = "Smart sort"
    case completedFirst = "Completed first"
    case uncompletedFirst = "Incomplete first"
    case easiestFirst = "Easiest first"
    case hardestFirst = "Hardest first"
    
    var id: String { self.rawValue }
    
    var iconName: String {
        switch self {
        case .smartSort: return "sparkles"
        case .completedFirst: return "checkmark.circle.fill"
        case .uncompletedFirst: return "circle.dashed"
        case .easiestFirst: return "arrow.down.right.circle"
        case .hardestFirst: return "arrow.up.right.circle"
        }
    }
}

// MARK: - Personas
public enum UserPersona: CaseIterable, Equatable {
    case observer
    case explorer
    case naturalist
    case scholar
    case apexObserver
    
    public init(speciesCount: Int) {
        switch speciesCount {
        case 0: self = .observer
        case 1..<10: self = .explorer
        case 10..<50: self = .naturalist
        case 50..<100: self = .scholar
        default: self = .apexObserver
        }
    }
    
    public var title: String {
        switch self {
        case .observer: return "New Observer"
        case .explorer: return "Casual Explorer"
        case .naturalist: return "Dedicated Naturalist"
        case .scholar: return "Verified Scholar"
        case .apexObserver: return "Apex Observer"
        }
    }
    
    public var description: String {
        switch self {
        case .observer: return "The viewfinder is ready. Step outside to log your first scan."
        case .explorer: return "Starting your collection. Learning the language of local flora and fauna."
        case .naturalist: return "Mapping local biodiversity and building a vibrant library."
        case .scholar: return "Curating a museum-grade archive of the natural world."
        case .apexObserver: return "An absolute authority on the ecosystem. Your collection is a masterpiece."
        }
    }
    
    public var imageName: String {
        switch self {
        case .observer: return "persona-observer"
        case .explorer: return "persona-explorer"
        case .naturalist: return "persona-naturalist"
        case .scholar: return "persona-scholar"
        case .apexObserver: return "persona-apex-observer"
        }
    }
    
    public var nextLevelThreshold: Int? {
        switch self {
        case .observer: return 1
        case .explorer: return 10
        case .naturalist: return 50
        case .scholar: return 100
        case .apexObserver: return nil
        }
    }
    
    public var nextLevelTitle: String? {
        switch self {
        case .observer: return UserPersona.explorer.title
        case .explorer: return UserPersona.naturalist.title
        case .naturalist: return UserPersona.scholar.title
        case .scholar: return UserPersona.apexObserver.title
        case .apexObserver: return nil
        }
    }
}

private extension String {
    var trimmedLowercased: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var trimmedUppercased: String {
        trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    var normalizedScientificName: String {
        trimmedLowercased
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
