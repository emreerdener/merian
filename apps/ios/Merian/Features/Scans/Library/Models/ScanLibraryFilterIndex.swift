import Foundation

/// Immutable scalar projection of one library record.
///
/// SwiftData models stay on their owning actor. `ScansManager` extracts these values in
/// yielding batches, then constructs `ScanLibraryFilterIndexSnapshot` on a detached task.
struct RawScanFilterSnapshot: Sendable {
    let id: String
    let captureDate: Date
    let hasLocation: Bool
    let hasImage: Bool
    let hasVideo: Bool
    let hasAudio: Bool
    let customTags: [String]
    let isInvasive: Bool
    let hazardType: String?
    let conservationStatus: String?
    let lifeStage: String?
    let ecologyType: String?
    let hasPetIdentification: Bool
    let imageQualityScore: Int?
    let isCorrectedIdentification: Bool
    let isConfirmedIdentification: Bool
    let weatherCondition: String?
    let taxonomyKingdom: String?
    let taxonomyClass: String?
    let taxonomyOrder: String?
    let taxonomyFamily: String?
    let taxonomyGenus: String?
    let isSharedToExplore: Bool

    @MainActor
    init(record: LocalScanRecord, isSharedToExplore: Bool) {
        let mediaSummary = record.capturedMediaSnapshot.summary
        let hasLegacyCoverImage = record.coverImagePath?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false

        self.id = record.id
        self.captureDate = record.captureDate ?? record.timestamp
        self.hasLocation = record.gpsLatitude != nil
            || record.gpsLongitude != nil
            || ScanLibraryFilterNormalizer.normalize(record.locationName) != nil
        self.hasImage = mediaSummary.hasImage || hasLegacyCoverImage
        self.hasVideo = mediaSummary.hasVideo
        self.hasAudio = mediaSummary.hasAudio
        self.customTags = record.customTags
        self.isInvasive = record.isInvasive
        self.hazardType = record.hazardType
        self.conservationStatus = record.iucnRedListStatus
        self.lifeStage = record.lifeStage
        self.ecologyType = record.ecologyType
        self.hasPetIdentification = record.petIdentification != nil
        self.imageQualityScore = record.imageQualityScore
        self.isCorrectedIdentification = record.userIdentificationOverride != nil
        self.isConfirmedIdentification =
            record.userConfirmedIdentification || record.confirmedSpeciesId != nil
        self.weatherCondition = record.weatherCondition
        self.taxonomyKingdom = record.taxonomyKingdom
        self.taxonomyClass = record.taxonomyClass
        self.taxonomyOrder = record.taxonomyOrder
        self.taxonomyFamily = record.taxonomyFamily
        self.taxonomyGenus = record.taxonomyGenus
        self.isSharedToExplore = isSharedToExplore
    }
}

/// Pre-normalized values used by every advanced-filter pass.
struct ScanLibraryFilterDocument: Sendable {
    let id: String
    let captureDate: Date
    let hasLocation: Bool
    let hasImage: Bool
    let hasVideo: Bool
    let hasAudio: Bool
    let customTags: Set<String>
    let isInvasive: Bool
    let hazardType: String?
    let conservationStatus: String?
    let lifeStage: String?
    let ecologyType: String?
    let hasPetIdentification: Bool
    let imageQualityScore: Int?
    let isCorrectedIdentification: Bool
    let isConfirmedIdentification: Bool
    let weatherCondition: String?
    let season: ScanSeasonFilter?
    let taxonomyClass: String?
    let taxonomyOrder: String?
    let taxonomyFamily: String?
    let taxonomyGenus: String?
    let isSharedToExplore: Bool

    init(raw: RawScanFilterSnapshot, calendar: Calendar) {
        id = raw.id
        captureDate = raw.captureDate
        hasLocation = raw.hasLocation
        hasImage = raw.hasImage
        hasVideo = raw.hasVideo
        hasAudio = raw.hasAudio
        customTags = Set(raw.customTags.compactMap { ScanLibraryFilterNormalizer.normalize($0) })
        isInvasive = raw.isInvasive
        hazardType = ScanLibraryFilterNormalizer.normalize(raw.hazardType)
        conservationStatus = ScanLibraryFilterNormalizer.normalize(raw.conservationStatus)
        lifeStage = ScanLibraryFilterNormalizer.normalize(raw.lifeStage)
        ecologyType = ScanLibraryFilterNormalizer.normalize(raw.ecologyType)
        hasPetIdentification = raw.hasPetIdentification
        imageQualityScore = raw.imageQualityScore
        isCorrectedIdentification = raw.isCorrectedIdentification
        isConfirmedIdentification = raw.isConfirmedIdentification
        weatherCondition = ScanLibraryFilterNormalizer.normalize(raw.weatherCondition)
        season = Self.season(for: calendar.component(.month, from: raw.captureDate))
        taxonomyClass = ScanLibraryFilterNormalizer.normalize(raw.taxonomyClass)
        taxonomyOrder = ScanLibraryFilterNormalizer.normalize(raw.taxonomyOrder)
        taxonomyFamily = ScanLibraryFilterNormalizer.normalize(raw.taxonomyFamily)
        taxonomyGenus = ScanLibraryFilterNormalizer.normalize(raw.taxonomyGenus)
        isSharedToExplore = raw.isSharedToExplore
    }

    private static func season(for month: Int) -> ScanSeasonFilter? {
        switch month {
        case 3...5:
            return .spring
        case 6...8:
            return .summer
        case 9...11:
            return .fall
        case 1, 2, 12:
            return .winter
        default:
            return nil
        }
    }
}

/// A lower-inclusive, upper-exclusive date range.
struct ScanLibraryDateRange: Sendable {
    let lowerBound: Date?
    let upperBound: Date?

    func contains(_ date: Date) -> Bool {
        if let lowerBound, date < lowerBound { return false }
        if let upperBound, date >= upperBound { return false }
        return lowerBound != nil || upperBound != nil
    }
}

/// Query projection created once per UI filter change.
///
/// User-selected strings are normalized once here rather than once for every record.
struct ScanLibraryFilterQuery: Sendable {
    let hasAdvancedFilters: Bool
    let requiresDateMatch: Bool
    let dateRanges: [ScanLibraryDateRange]
    let locationFilters: Set<ScanLocationFilter>
    let mediaFilters: Set<ScanMediaFilter>
    let customTags: Set<String>
    let isInvasive: Bool
    let requiresHazardTypeMatch: Bool
    let hazardTypes: Set<String>
    let requiresConservationStatusMatch: Bool
    let conservationStatuses: Set<String>
    let requiresLifeStageMatch: Bool
    let lifeStages: Set<String>
    let ecologyFilters: Set<ScanEcologyFilter>
    let qualityFilters: Set<ScanQualityFilter>
    let identificationFilters: Set<ScanIdentificationFilter>
    let requiresWeatherConditionMatch: Bool
    let weatherConditions: Set<String>
    let seasons: Set<ScanSeasonFilter>
    let requiresTaxonomyClassMatch: Bool
    let taxonomyClasses: Set<String>
    let requiresTaxonomyOrderMatch: Bool
    let taxonomyOrders: Set<String>
    let requiresTaxonomyFamilyMatch: Bool
    let taxonomyFamilies: Set<String>
    let requiresTaxonomyGenusMatch: Bool
    let taxonomyGenera: Set<String>
    let explorePostFilters: Set<ScanExplorePostFilter>

    init(filters: ScanLibraryFilters, now: Date = Date(), calendar: Calendar = .current) {
        hasAdvancedFilters = filters.hasAdvancedFilters
        requiresDateMatch = !filters.dateFilters.isEmpty

        var ranges: [ScanLibraryDateRange] = []
        ranges.reserveCapacity(filters.dateFilters.count)
        for filter in filters.dateFilters {
            switch filter {
            case .today:
                if let interval = calendar.dateInterval(of: .day, for: now) {
                    ranges.append(.init(lowerBound: interval.start, upperBound: interval.end))
                }
            case .thisWeek:
                if let interval = calendar.dateInterval(of: .weekOfYear, for: now) {
                    ranges.append(.init(lowerBound: interval.start, upperBound: interval.end))
                }
            case .thisMonth:
                if let interval = calendar.dateInterval(of: .month, for: now) {
                    ranges.append(.init(lowerBound: interval.start, upperBound: interval.end))
                }
            case .thisYear:
                if let interval = calendar.dateInterval(of: .year, for: now) {
                    ranges.append(.init(lowerBound: interval.start, upperBound: interval.end))
                }
            case .custom:
                let lowerBound = filters.customStartDate.map { calendar.startOfDay(for: $0) }
                let upperBound = filters.customEndDate.flatMap {
                    calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0))
                }
                if lowerBound != nil || upperBound != nil {
                    ranges.append(.init(lowerBound: lowerBound, upperBound: upperBound))
                }
            }
        }
        dateRanges = ranges

        locationFilters = filters.locationFilters
        mediaFilters = filters.mediaFilters
        customTags = Self.normalized(filters.customTags)
        isInvasive = filters.isInvasive
        requiresHazardTypeMatch = !filters.hazardTypes.isEmpty
        hazardTypes = Self.normalized(filters.hazardTypes)
        requiresConservationStatusMatch = !filters.conservationStatuses.isEmpty
        conservationStatuses = Self.normalized(filters.conservationStatuses)
        requiresLifeStageMatch = !filters.lifeStages.isEmpty
        lifeStages = Self.normalized(filters.lifeStages)
        ecologyFilters = filters.ecologyFilters
        qualityFilters = filters.qualityFilters
        identificationFilters = filters.identificationFilters
        requiresWeatherConditionMatch = !filters.weatherConditions.isEmpty
        weatherConditions = Self.normalized(filters.weatherConditions)
        seasons = filters.seasons
        requiresTaxonomyClassMatch = !filters.taxonomyClasses.isEmpty
        taxonomyClasses = Self.normalized(filters.taxonomyClasses)
        requiresTaxonomyOrderMatch = !filters.taxonomyOrders.isEmpty
        taxonomyOrders = Self.normalized(filters.taxonomyOrders)
        requiresTaxonomyFamilyMatch = !filters.taxonomyFamilies.isEmpty
        taxonomyFamilies = Self.normalized(filters.taxonomyFamilies)
        requiresTaxonomyGenusMatch = !filters.taxonomyGenera.isEmpty
        taxonomyGenera = Self.normalized(filters.taxonomyGenera)
        explorePostFilters = filters.explorePostFilters
    }

    private static func normalized(_ values: Set<String>) -> Set<String> {
        Set(values.compactMap { ScanLibraryFilterNormalizer.normalize($0) })
    }

    func matches(_ document: ScanLibraryFilterDocument) -> Bool {
        if requiresDateMatch, !dateRanges.contains(where: { $0.contains(document.captureDate) }) {
            return false
        }

        if !locationFilters.isEmpty {
            let locationMatches =
                (document.hasLocation && locationFilters.contains(.hasLocation))
                || (!document.hasLocation && locationFilters.contains(.noLocation))
            if !locationMatches { return false }
        }

        if !mediaFilters.isEmpty {
            let mediaMatches =
                (mediaFilters.contains(.image) && document.hasImage && !document.hasVideo)
                || (mediaFilters.contains(.video) && document.hasVideo)
                || (mediaFilters.contains(.audio) && document.hasAudio)
            if !mediaMatches { return false }
        }

        if !customTags.isEmpty, document.customTags.isDisjoint(with: customTags) {
            return false
        }
        if isInvasive, !document.isInvasive { return false }
        if !Self.matches(
            document.hazardType,
            selected: hazardTypes,
            isRequired: requiresHazardTypeMatch
        ) {
            return false
        }
        if !Self.matches(
            document.conservationStatus,
            selected: conservationStatuses,
            isRequired: requiresConservationStatusMatch
        ) {
            return false
        }
        if !Self.matches(
            document.lifeStage,
            selected: lifeStages,
            isRequired: requiresLifeStageMatch
        ) {
            return false
        }

        if !ecologyFilters.isEmpty {
            let ecologyMatches = ecologyFilters.contains { filter in
                switch filter {
                case .wild:
                    return document.ecologyType == "wild"
                case .captive:
                    return document.ecologyType == "captive"
                case .domesticated:
                    return document.ecologyType == "domesticated"
                case .pet:
                    return document.hasPetIdentification || document.ecologyType == "pet"
                }
            }
            if !ecologyMatches { return false }
        }

        if !qualityFilters.isEmpty {
            let qualityMatches = qualityFilters.contains { filter in
                switch filter {
                case .highQuality:
                    return (document.imageQualityScore ?? -1) >= 80
                case .mediumQuality:
                    guard let score = document.imageQualityScore else { return false }
                    return score >= 60 && score < 80
                case .lowQuality:
                    guard let score = document.imageQualityScore else { return false }
                    return score < 60
                case .noScore:
                    return document.imageQualityScore == nil
                }
            }
            if !qualityMatches { return false }
        }

        if !identificationFilters.isEmpty {
            let identificationMatches = identificationFilters.contains { filter in
                switch filter {
                case .confirmed:
                    return document.isConfirmedIdentification
                case .corrected:
                    return document.isCorrectedIdentification
                case .aiOnly:
                    return !document.isConfirmedIdentification
                        && !document.isCorrectedIdentification
                }
            }
            if !identificationMatches { return false }
        }

        if !Self.matches(
            document.weatherCondition,
            selected: weatherConditions,
            isRequired: requiresWeatherConditionMatch
        ) {
            return false
        }
        if !seasons.isEmpty {
            guard let season = document.season, seasons.contains(season) else { return false }
        }

        if !Self.matches(
            document.taxonomyClass,
            selected: taxonomyClasses,
            isRequired: requiresTaxonomyClassMatch
        ) {
            return false
        }
        if !Self.matches(
            document.taxonomyOrder,
            selected: taxonomyOrders,
            isRequired: requiresTaxonomyOrderMatch
        ) {
            return false
        }
        if !Self.matches(
            document.taxonomyFamily,
            selected: taxonomyFamilies,
            isRequired: requiresTaxonomyFamilyMatch
        ) {
            return false
        }
        if !Self.matches(
            document.taxonomyGenus,
            selected: taxonomyGenera,
            isRequired: requiresTaxonomyGenusMatch
        ) {
            return false
        }

        if explorePostFilters.contains(.shared), !document.isSharedToExplore {
            return false
        }

        return true
    }

    private static func matches(
        _ value: String?,
        selected: Set<String>,
        isRequired: Bool
    ) -> Bool {
        guard isRequired else { return true }
        guard let value else { return false }
        return selected.contains(value)
    }
}

/// Generation-scoped immutable index used by the filter sheet and detached query worker.
struct ScanLibraryFilterIndexSnapshot: Sendable {
    static let empty = ScanLibraryFilterIndexSnapshot(rawSnapshots: [])

    let documentsById: [String: ScanLibraryFilterDocument]
    let allDocumentIDs: [String]
    let filterOptions: ScanLibraryFilterOptions
    let orderedCategoryFilters: [String]

    var count: Int { documentsById.count }

    init(rawSnapshots: [RawScanFilterSnapshot]) {
        let calendar = Calendar.current
        var documents: [String: ScanLibraryFilterDocument] = [:]
        documents.reserveCapacity(rawSnapshots.count)
        var allIDs: [String] = []
        allIDs.reserveCapacity(rawSnapshots.count)

        var customTags: [String: String] = [:]
        var hazardTypes: [String: String] = [:]
        var conservationStatuses: [String: String] = [:]
        var lifeStages: [String: String] = [:]
        var weatherConditions: [String: String] = [:]
        var taxonomyClasses: [String: String] = [:]
        var taxonomyOrders: [String: String] = [:]
        var taxonomyFamilies: [String: String] = [:]
        var taxonomyGenera: [String: String] = [:]
        var categoryCounts: [SearchCategoryBucket: Int] = [:]

        for raw in rawSnapshots {
            if Task.isCancelled { break }

            documents[raw.id] = ScanLibraryFilterDocument(raw: raw, calendar: calendar)
            allIDs.append(raw.id)

            Self.addDisplayValues(raw.customTags, to: &customTags)
            Self.addDisplayValue(raw.hazardType, to: &hazardTypes)
            Self.addDisplayValue(raw.conservationStatus, to: &conservationStatuses)
            Self.addDisplayValue(raw.lifeStage, to: &lifeStages)
            Self.addDisplayValue(raw.weatherCondition, to: &weatherConditions)
            Self.addDisplayValue(raw.taxonomyClass, to: &taxonomyClasses)
            Self.addDisplayValue(raw.taxonomyOrder, to: &taxonomyOrders)
            Self.addDisplayValue(raw.taxonomyFamily, to: &taxonomyFamilies)
            Self.addDisplayValue(raw.taxonomyGenus, to: &taxonomyGenera)

            let category = SearchCategoryBucket(
                kingdom: raw.taxonomyKingdom?.lowercased() ?? "",
                className: raw.taxonomyClass?.lowercased() ?? ""
            )
            categoryCounts[category, default: 0] += 1
        }

        documentsById = documents
        allDocumentIDs = allIDs
        filterOptions = ScanLibraryFilterOptions(
            customTags: Self.sortedDisplayValues(customTags),
            hazardTypes: Self.sortedDisplayValues(hazardTypes),
            conservationStatuses: Self.sortedDisplayValues(conservationStatuses),
            lifeStages: Self.sortedDisplayValues(lifeStages),
            weatherConditions: Self.sortedDisplayValues(weatherConditions),
            taxonomyClasses: Self.sortedDisplayValues(taxonomyClasses),
            taxonomyOrders: Self.sortedDisplayValues(taxonomyOrders),
            taxonomyFamilies: Self.sortedDisplayValues(taxonomyFamilies),
            taxonomyGenera: Self.sortedDisplayValues(taxonomyGenera)
        )

        let priority = Dictionary(
            uniqueKeysWithValues: SearchCategoryBucket.libraryFilterPriority.enumerated().map { ($1, $0) }
        )
        let orderedCategories = SearchCategoryBucket.libraryFilterPriority.sorted { lhs, rhs in
            let lhsCount = categoryCounts[lhs, default: 0]
            let rhsCount = categoryCounts[rhs, default: 0]
            if lhsCount != rhsCount {
                return lhsCount > rhsCount
            }
            return priority[lhs, default: .max] < priority[rhs, default: .max]
        }
        orderedCategoryFilters = ["All"] + orderedCategories.map(\.title)
    }

    func matchingIDs(in candidateIDs: [String], query: ScanLibraryFilterQuery) -> [String] {
        guard query.hasAdvancedFilters else { return candidateIDs }

        var matchingIDs: [String] = []
        matchingIDs.reserveCapacity(candidateIDs.count)
        for id in candidateIDs {
            if Task.isCancelled { return [] }
            guard let document = documentsById[id], query.matches(document) else { continue }
            matchingIDs.append(id)
        }
        return matchingIDs
    }

    private static func addDisplayValues(_ values: [String], to result: inout [String: String]) {
        for value in values {
            addDisplayValue(value, to: &result)
        }
    }

    private static func addDisplayValue(_ value: String?, to result: inout [String: String]) {
        guard let value,
              let normalized = ScanLibraryFilterNormalizer.normalize(value) else {
            return
        }
        result[normalized] = result[normalized]
            ?? value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sortedDisplayValues(_ values: [String: String]) -> [String] {
        values.values.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
}

enum ScanLibraryFilterNormalizer {
    static func normalize(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, normalized != "none", normalized != "unknown" else {
            return nil
        }
        return normalized
    }
}
