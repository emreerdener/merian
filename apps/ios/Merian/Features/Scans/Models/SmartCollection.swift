import Foundation

struct SmartCollectionDefinition: Identifiable, Equatable {
    enum Rule: Equatable {
        case needsReview
        case recentFinds
        case shared
        case location(String)
        case taxonomy(SearchCategoryBucket)
        case invasive
        case hazards
    }

    let id: String
    let title: String
    let iconName: String
    let rule: Rule
    let rank: Int
}

struct SmartCollectionSnapshot: Identifiable {
    let definition: SmartCollectionDefinition
    let scans: [LocalScanRecord]
    let coverScan: LocalScanRecord?

    var id: String { definition.id }
    var title: String { definition.title }
    var iconName: String { definition.iconName }
    var count: Int { scans.count }
    var newestScanDate: Date { scans.map(\.timestamp).max() ?? .distantPast }
}

enum SmartCollectionSuggester {
    private static let maximumSuggestions = 6
    private static let minimumRecentScans = 3
    private static let minimumReviewScans = 2
    private static let minimumSharedScans = 1
    private static let minimumTaxonomyScans = 3
    private static let minimumLocationScans = 3
    private static let minimumSpecialScans = 2
    private static let recentWindow: TimeInterval = 30 * 24 * 60 * 60
    private static let taxonomyLibraryShare = 0.2

    static func suggestions(
        from scans: [LocalScanRecord],
        existingCollections: [ScanCollection],
        hiddenCollectionIDs: Set<String> = [],
        sharedPostIDProvider: (String) -> String? = { ExploreShareStateStore.sharedPostId(for: $0) },
        referenceDate: Date = Date()
    ) -> [SmartCollectionSnapshot] {
        let activeCollectionNames = Set(
            existingCollections
                .filter { !$0.isDeleted }
                .map { normalizedCollectionName($0.name) }
        )

        let biologicalScans = scans
            .filter { $0.isBiological }
            .sortedByNewest()

        guard !biologicalScans.isEmpty else { return [] }

        var snapshots: [SmartCollectionSnapshot] = []

        appendReviewSuggestion(to: &snapshots, scans: biologicalScans)
        appendRecentSuggestion(to: &snapshots, scans: biologicalScans, referenceDate: referenceDate)
        appendSharedSuggestion(to: &snapshots, scans: biologicalScans, sharedPostIDProvider: sharedPostIDProvider)
        appendLocationSuggestions(to: &snapshots, scans: biologicalScans)
        appendTaxonomySuggestions(to: &snapshots, scans: biologicalScans)
        appendSpecialSuggestions(to: &snapshots, scans: biologicalScans)

        return snapshots
            .filter { !activeCollectionNames.contains(normalizedCollectionName($0.title)) }
            .filter { !hiddenCollectionIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.definition.rank != rhs.definition.rank {
                    return lhs.definition.rank < rhs.definition.rank
                }
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return lhs.newestScanDate > rhs.newestScanDate
            }
            .prefix(maximumSuggestions)
            .map { $0 }
    }

    static func refreshedSnapshot(
        for snapshot: SmartCollectionSnapshot,
        from scans: [LocalScanRecord],
        referenceDate: Date = Date()
    ) -> SmartCollectionSnapshot {
        let biologicalScans = scans
            .filter { $0.isBiological }
            .sortedByNewest()
        let matchingScans = matchingScans(
            for: snapshot.definition,
            in: biologicalScans,
            referenceDate: referenceDate
        ).sortedByNewest()
        return SmartCollectionSnapshot(
            definition: snapshot.definition,
            scans: matchingScans,
            coverScan: matchingScans.first
        )
    }

    static func normalizedCollectionName(_ name: String) -> String {
        normalize(name)
    }

    static func normalizedLocationName(_ name: String?) -> String? {
        guard let value = name else { return nil }
        let normalized = normalize(value)
        return normalized.isEmpty ? nil : normalized
    }

    private static func appendReviewSuggestion(
        to snapshots: inout [SmartCollectionSnapshot],
        scans: [LocalScanRecord]
    ) {
        let matches = scans.filter(isReviewCandidate)
        append(
            to: &snapshots,
            title: "Needs review",
            iconName: "checkmark.seal",
            rule: .needsReview,
            rank: 0,
            scans: matches,
            minimumCount: minimumReviewScans
        )
    }

    private static func appendRecentSuggestion(
        to snapshots: inout [SmartCollectionSnapshot],
        scans: [LocalScanRecord],
        referenceDate: Date
    ) {
        let cutoff = referenceDate.addingTimeInterval(-recentWindow)
        let matches = scans.filter { $0.timestamp >= cutoff && $0.timestamp <= referenceDate }
        append(
            to: &snapshots,
            title: "Recent finds",
            iconName: "clock",
            rule: .recentFinds,
            rank: 1,
            scans: matches,
            minimumCount: minimumRecentScans
        )
    }

    private static func appendSharedSuggestion(
        to snapshots: inout [SmartCollectionSnapshot],
        scans: [LocalScanRecord],
        sharedPostIDProvider: (String) -> String?
    ) {
        let matches = scans.filter { sharedPostIDProvider($0.id) != nil }
        append(
            to: &snapshots,
            title: "Explore posts",
            iconName: "globe.americas",
            rule: .shared,
            rank: 2,
            scans: matches,
            minimumCount: minimumSharedScans
        )
    }

    private static func appendLocationSuggestions(
        to snapshots: inout [SmartCollectionSnapshot],
        scans: [LocalScanRecord]
    ) {
        let grouped = Dictionary(grouping: scans) { scan in
            normalizedLocationName(scan.locationName) ?? ""
        }
        let rankedGroups = grouped
            .filter { !$0.key.isEmpty && $0.value.count >= minimumLocationScans }
            .sorted { lhs, rhs in
                if lhs.value.count != rhs.value.count {
                    return lhs.value.count > rhs.value.count
                }
                return newestDate(in: lhs.value) > newestDate(in: rhs.value)
            }
            .prefix(2)

        for (_, groupScans) in rankedGroups {
            guard let displayName = displayLocationName(from: groupScans) else { continue }
            append(
                to: &snapshots,
                title: displayName,
                iconName: "mappin.and.ellipse",
                rule: .location(normalize(displayName)),
                rank: 3,
                scans: groupScans,
                minimumCount: minimumLocationScans
            )
        }
    }

    private static func appendTaxonomySuggestions(
        to snapshots: inout [SmartCollectionSnapshot],
        scans: [LocalScanRecord]
    ) {
        let minimumShareCount = Int(ceil(Double(scans.count) * taxonomyLibraryShare))
        let grouped = Dictionary(grouping: scans) { scan in
            SearchCategoryBucket(
                kingdom: scan.taxonomyKingdom?.lowercased() ?? "",
                className: scan.taxonomyClass?.lowercased() ?? ""
            )
        }

        let rankedGroups = grouped
            .filter { bucket, groupScans in
                bucket != .other &&
                groupScans.count >= minimumTaxonomyScans &&
                groupScans.count >= minimumShareCount
            }
            .sorted { lhs, rhs in
                if lhs.value.count != rhs.value.count {
                    return lhs.value.count > rhs.value.count
                }
                return newestDate(in: lhs.value) > newestDate(in: rhs.value)
            }
            .prefix(2)

        for (bucket, groupScans) in rankedGroups {
            append(
                to: &snapshots,
                title: bucket.displayTitle,
                iconName: bucket.iconName,
                rule: .taxonomy(bucket),
                rank: 4,
                scans: groupScans,
                minimumCount: minimumTaxonomyScans
            )
        }
    }

    private static func appendSpecialSuggestions(
        to snapshots: inout [SmartCollectionSnapshot],
        scans: [LocalScanRecord]
    ) {
        append(
            to: &snapshots,
            title: "Invasive finds",
            iconName: "exclamationmark.triangle",
            rule: .invasive,
            rank: 5,
            scans: scans.filter(\.isInvasive),
            minimumCount: minimumSpecialScans
        )

        append(
            to: &snapshots,
            title: "Potential hazards",
            iconName: "cross.case",
            rule: .hazards,
            rank: 6,
            scans: scans.filter { $0.hazardType.lowercased() != "none" },
            minimumCount: minimumSpecialScans
        )
    }

    private static func append(
        to snapshots: inout [SmartCollectionSnapshot],
        title: String,
        iconName: String,
        rule: SmartCollectionDefinition.Rule,
        rank: Int,
        scans: [LocalScanRecord],
        minimumCount: Int
    ) {
        let sortedScans = scans.sortedByNewest()
        guard sortedScans.count >= minimumCount else { return }

        let definition = SmartCollectionDefinition(
            id: normalize(title),
            title: title,
            iconName: iconName,
            rule: rule,
            rank: rank
        )
        snapshots.append(SmartCollectionSnapshot(
            definition: definition,
            scans: sortedScans,
            coverScan: sortedScans.first
        ))
    }

    private static func isReviewCandidate(_ scan: LocalScanRecord) -> Bool {
        guard scan.userReviewState == .unreviewed else { return false }
        guard let confidenceScore = scan.confidenceScore else { return false }
        let threshold = MerianConfig.confidenceBands(forInferenceTier: scan.inferenceTier).possible
        return confidenceScore < threshold
    }

    private static func matchingScans(
        for definition: SmartCollectionDefinition,
        in scans: [LocalScanRecord],
        referenceDate: Date
    ) -> [LocalScanRecord] {
        switch definition.rule {
        case .needsReview:
            return scans.filter(isReviewCandidate)
        case .recentFinds:
            let cutoff = referenceDate.addingTimeInterval(-recentWindow)
            return scans.filter { $0.timestamp >= cutoff && $0.timestamp <= referenceDate }
        case .shared:
            return scans.filter { ExploreShareStateStore.sharedPostId(for: $0.id) != nil }
        case .location(let normalizedLocation):
            return scans.filter { normalizedLocationName($0.locationName) == normalizedLocation }
        case .taxonomy(let bucket):
            return scans.filter { scan in
                SearchCategoryBucket(
                    kingdom: scan.taxonomyKingdom?.lowercased() ?? "",
                    className: scan.taxonomyClass?.lowercased() ?? ""
                ) == bucket
            }
        case .invasive:
            return scans.filter(\.isInvasive)
        case .hazards:
            return scans.filter { $0.hazardType.lowercased() != "none" }
        }
    }

    private static func displayLocationName(from scans: [LocalScanRecord]) -> String? {
        scans
            .sortedByNewest()
            .compactMap { scan -> String? in
                let trimmed = scan.locationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
            .first
    }

    private static func newestDate(in scans: [LocalScanRecord]) -> Date {
        scans.map(\.timestamp).max() ?? .distantPast
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

enum SmartCollectionPreferences {
    static func hiddenIDs(defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: UserDefaultsKeys.hiddenSmartCollectionIDs) ?? [])
    }

    @discardableResult
    static func hide(id: String, defaults: UserDefaults = .standard) -> Set<String> {
        var ids = hiddenIDs(defaults: defaults)
        ids.insert(id)
        persistHiddenIDs(ids, defaults: defaults)
        return ids
    }

    static func clearHiddenIDs(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: UserDefaultsKeys.hiddenSmartCollectionIDs)
    }

    private static func persistHiddenIDs(_ ids: Set<String>, defaults: UserDefaults) {
        defaults.set(ids.sorted(), forKey: UserDefaultsKeys.hiddenSmartCollectionIDs)
    }
}

private extension Array where Element == LocalScanRecord {
    func sortedByNewest() -> [LocalScanRecord] {
        sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            return lhs.id < rhs.id
        }
    }
}

private extension SearchCategoryBucket {
    var displayTitle: String {
        switch self {
        case .plants: return "Plants"
        case .fungi: return "Fungi"
        case .insects: return "Insects"
        case .birds: return "Birds"
        case .mammals: return "Mammals"
        case .reptiles: return "Reptiles"
        case .other: return "Other finds"
        }
    }

    var iconName: String {
        switch self {
        case .plants: return "leaf"
        case .fungi: return "circle.hexagongrid"
        case .insects: return "ladybug"
        case .birds: return "bird"
        case .mammals: return "pawprint"
        case .reptiles: return "lizard"
        case .other: return "sparkles"
        }
    }
}
