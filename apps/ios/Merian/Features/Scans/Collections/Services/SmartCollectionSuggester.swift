import Foundation

enum SmartCollectionSuggester {
    private static let maximumSuggestions = 6
    private static let maximumFeaturedScans = 24
    private static let minimumRecentScans = 3
    private static let minimumReviewScans = 2
    private static let minimumSharedScans = 1
    private static let minimumTaxonomyScans = 3
    private static let minimumLocationScans = 3
    private static let minimumSpecialScans = 2
    private static let dayInterval: TimeInterval = 24 * 60 * 60
    private static let recentWindow: TimeInterval = 30 * dayInterval
    private static let taxonomyLibraryShare = 0.2

    static func suggestions(
        from scans: [LocalScanRecord],
        existingCollections: [ScanCollection],
        hiddenCollectionIDs: Set<String> = [],
        sharedPostIDProvider: (String) -> String? = { _ in nil },
        referenceDate: Date = Date()
    ) -> [SmartCollectionSnapshot] {
        let activeCollectionNames = Set(
            existingCollections
                .filter { !$0.isPendingDeletion }
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
            .filter { !$0.isHideable || !hiddenCollectionIDs.contains($0.id) }
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

    static func featuredSnapshot(
        from scans: [LocalScanRecord],
        hiddenCollectionIDs: Set<String> = [],
        referenceDate: Date = Date()
    ) -> SmartCollectionSnapshot? {
        let featuredScans = dailyFeaturedScans(from: scans, referenceDate: referenceDate)
        guard !featuredScans.isEmpty else { return nil }

        let definition = SmartCollectionDefinition(
            id: normalize("Featured scans"),
            title: "Featured scans",
            iconName: "sparkles",
            rule: .featured,
            rank: -1
        )
        guard !hiddenCollectionIDs.contains(definition.id) else { return nil }

        return SmartCollectionSnapshot(
            definition: definition,
            scans: featuredScans,
            coverScan: featuredScans.first
        )
    }

    static func refreshedSnapshot(
        for snapshot: SmartCollectionSnapshot,
        from scans: [LocalScanRecord],
        sharedPostIDProvider: (String) -> String? = { _ in nil },
        referenceDate: Date = Date()
    ) -> SmartCollectionSnapshot {
        let biologicalScans = scans
            .filter { $0.isBiological }
            .sortedByNewest()
        let matchingScans = matchingScans(
            for: snapshot.definition,
            in: biologicalScans,
            sharedPostIDProvider: sharedPostIDProvider,
            referenceDate: referenceDate
        ).sortedByNewest()
        return SmartCollectionSnapshot(
            definition: snapshot.definition,
            scans: matchingScans,
            coverScan: coverScan(
                for: snapshot.definition.rule,
                title: snapshot.definition.title,
                from: matchingScans
            )
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
            coverScan: coverScan(
                for: rule,
                title: title,
                from: sortedScans
            )
        ))
    }

    private static func coverScan(
        for rule: SmartCollectionDefinition.Rule,
        title: String,
        from sortedScans: [LocalScanRecord]
    ) -> LocalScanRecord? {
        let eligibleScans = sortedScans.filter(CollectionCoverPolicy.isEligible)
        let coverCandidates = eligibleScans.isEmpty ? sortedScans : eligibleScans

        switch rule {
        case .featured:
            return coverCandidates.first
        case .recentFinds:
            return coverCandidates.first
        default:
            return stableRandomScan(from: coverCandidates, seed: normalize(title))
        }
    }

    private static func stableRandomScan(from scans: [LocalScanRecord], seed: String) -> LocalScanRecord? {
        guard !scans.isEmpty else { return nil }

        let stableSeed = ([seed] + scans.map(\.id)).joined(separator: "|")
        return scans[Int(stableHash(stableSeed) % UInt64(scans.count))]
    }

    private static func dailyFeaturedScans(
        from scans: [LocalScanRecord],
        referenceDate: Date
    ) -> [LocalScanRecord] {
        let sortedScans = scans
            .filter { $0.isBiological }
            .sortedByNewest()

        guard sortedScans.count > maximumFeaturedScans else {
            return sortedScans
        }

        let daySeed = Int(floor(referenceDate.timeIntervalSince1970 / dayInterval))
        return sortedScans
            .map { scan in
                (
                    scan: scan,
                    rank: stableHash("\(daySeed)|\(scan.id)")
                )
            }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank {
                    return lhs.rank < rhs.rank
                }
                if lhs.scan.timestamp != rhs.scan.timestamp {
                    return lhs.scan.timestamp > rhs.scan.timestamp
                }
                return lhs.scan.id < rhs.scan.id
            }
            .prefix(maximumFeaturedScans)
            .map(\.scan)
    }

    private static func stableHash(_ value: String) -> UInt64 {
        value.unicodeScalars.reduce(UInt64(14_695_981_039_346_656_037)) { result, scalar in
            (result ^ UInt64(scalar.value)) &* 1_099_511_628_211
        }
    }

    private static func isReviewCandidate(_ scan: LocalScanRecord) -> Bool {
        guard scan.userReviewState == .unreviewed else { return false }
        return CandidateReviewVisibilityPolicy.shouldSurfaceForReviewCollection(
            primaryConfidence: scan.confidenceScore,
            inferenceTier: scan.inferenceTier,
            candidates: decodedCandidates(from: scan.candidatesData),
            isBiological: scan.isBiological,
            isUnknownSubject: scan.scientificName == LocalScanRecord.unresolvedBiologicalScientificName,
            isHumanSubject: scan.isHumanSubject,
            userIdentificationOverride: scan.userIdentificationOverride,
            userConfirmedIdentification: scan.userConfirmedIdentification,
            isFlagged: scan.isFlagged
        )
    }

    private static func decodedCandidates(from data: Data?) -> [IdentificationCandidate] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([IdentificationCandidate].self, from: data)) ?? []
    }

    private static func matchingScans(
        for definition: SmartCollectionDefinition,
        in scans: [LocalScanRecord],
        sharedPostIDProvider: (String) -> String?,
        referenceDate: Date
    ) -> [LocalScanRecord] {
        switch definition.rule {
        case .featured:
            return dailyFeaturedScans(from: scans, referenceDate: referenceDate)
        case .needsReview:
            return scans.filter(isReviewCandidate)
        case .recentFinds:
            let cutoff = referenceDate.addingTimeInterval(-recentWindow)
            return scans.filter { $0.timestamp >= cutoff && $0.timestamp <= referenceDate }
        case .shared:
            return scans.filter { sharedPostIDProvider($0.id) != nil }
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
