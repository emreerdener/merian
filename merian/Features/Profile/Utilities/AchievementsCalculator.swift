import Foundation

extension LocalScanRecord: AchievementRecordRepresentable {
    var imagePath: String? { scanThumbnailPresentation.imagePath }
    var fallbackImageUrl: String? { scanThumbnailPresentation.fallbackImageUrl }
    var placeholderStyle: ScanThumbnailPlaceholderStyle { scanThumbnailPresentation.placeholderStyle }
}

struct AchievementsCalculator {
    static func calculate<Record: AchievementRecordRepresentable>(from allRecords: [Record]) -> [AwardPayload] {
        evaluations(from: allRecords).map(\.award)
    }

    static func detail<Record: AchievementRecordRepresentable>(
        for type: AchievementType,
        from allRecords: [Record]
    ) -> AchievementDetailPayload? {
        evaluations(from: allRecords).first { $0.award.type == type }
    }

    private static func evaluations<Record: AchievementRecordRepresentable>(
        from allRecords: [Record]
    ) -> [AchievementDetailPayload] {
        var accumulators = Dictionary(
            uniqueKeysWithValues: AchievementType.allCases.compactMap { type -> (AchievementType, AchievementAccumulator)? in
                switch type.definition.contributionKind {
                case .firstScan:
                    return nil
                case .uniqueSpecies:
                    return (type, AchievementAccumulator(type: type))
                }
            }
        )

        for record in allRecords {
            for type in AchievementType.allCases {
                switch type.definition.contributionKind {
                case .firstScan:
                    continue
                case .uniqueSpecies(let qualifyingReason):
                    guard let reasonText = qualifyingReason(record) else { continue }
                    let contribution = makeContribution(for: record, reasonText: reasonText)
                    accumulators[type]?.register(
                        contribution,
                        canonicalSpeciesKey: record.canonicalSpeciesKey
                    )
                }
            }
        }

        return AchievementType.allCases.map { type in
            switch type.definition.contributionKind {
            case .firstScan(let reasonText):
                return firstScanDetail(from: allRecords, reasonText: reasonText)
            case .uniqueSpecies:
                return accumulators[type]?.detailPayload ?? AchievementDetailPayload(
                    award: AwardPayload(type: type, currentCount: 0, lastInteractionDate: nil),
                    contributions: []
                )
            }
        }
    }

    private static func firstScanDetail<Record: AchievementRecordRepresentable>(
        from allRecords: [Record],
        reasonText: String
    ) -> AchievementDetailPayload {
        let oldestRecord = allRecords.min { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id < rhs.id
            }
            return lhs.timestamp < rhs.timestamp
        }

        return AchievementDetailPayload(
            award: AwardPayload(
                type: .firstScan,
                currentCount: oldestRecord == nil ? 0 : 1,
                lastInteractionDate: oldestRecord?.timestamp
            ),
            contributions: oldestRecord.map {
                [makeContribution(for: $0, reasonText: reasonText)]
            } ?? []
        )
    }

    private static func makeContribution<Record: AchievementRecordRepresentable>(
        for record: Record,
        reasonText: String
    ) -> AchievementContribution {
        AchievementContribution(
            scanID: record.id,
            commonName: record.displayCommonName,
            scientificName: record.displayScientificName,
            timestamp: record.timestamp,
            reasonText: reasonText,
            imagePath: record.imagePath,
            fallbackImageUrl: record.fallbackImageUrl,
            placeholderStyle: record.placeholderStyle,
            locationName: record.locationName
        )
    }
}

private struct AchievementAccumulator {
    let type: AchievementType
    private var contributionsBySpeciesKey: [String: AchievementContribution] = [:]
    private var lastInteractionDate: Date?

    init(type: AchievementType) {
        self.type = type
    }

    mutating func register(
        _ contribution: AchievementContribution,
        canonicalSpeciesKey: String
    ) {
        if let existingContribution = contributionsBySpeciesKey[canonicalSpeciesKey],
           existingContribution.timestamp >= contribution.timestamp {
            lastInteractionDate = max(lastInteractionDate ?? existingContribution.timestamp, existingContribution.timestamp)
            return
        }

        contributionsBySpeciesKey[canonicalSpeciesKey] = contribution
        lastInteractionDate = max(lastInteractionDate ?? contribution.timestamp, contribution.timestamp)
    }

    var detailPayload: AchievementDetailPayload {
        AchievementDetailPayload(
            award: AwardPayload(
                type: type,
                currentCount: contributionsBySpeciesKey.count,
                lastInteractionDate: lastInteractionDate
            ),
            contributions: contributionsBySpeciesKey.values.sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.scanID < rhs.scanID
                }
                return lhs.timestamp > rhs.timestamp
            }
        )
    }
}
