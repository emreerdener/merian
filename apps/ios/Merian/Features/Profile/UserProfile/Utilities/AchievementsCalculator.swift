import Foundation

extension LocalScanRecord: AchievementRecordRepresentable {
    var imagePath: String? { scanThumbnailPresentation.imagePath }
    var fallbackImageUrl: String? { scanThumbnailPresentation.fallbackImageUrl }
    var audioPath: String? { scanThumbnailPresentation.audioPath }
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
                case .externalMilestone:
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
                case .externalMilestone:
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
            case .externalMilestone:
                return AchievementDetailPayload(
                    award: AwardPayload(type: type, currentCount: 0, lastInteractionDate: nil),
                    contributions: []
                )
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
                lastInteractionDate: oldestRecord?.timestamp,
                unlockedAt: oldestRecord?.timestamp
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
            timestamp: record.observationDate,
            reasonText: reasonText,
            imagePath: record.imagePath,
            fallbackImageUrl: record.fallbackImageUrl,
            audioPath: record.audioPath,
            placeholderStyle: record.placeholderStyle,
            locationName: record.locationName
        )
    }
}

private struct AchievementAccumulator {
    private struct SpeciesContributionHistory {
        private(set) var earliest: AchievementContribution
        private(set) var latest: AchievementContribution

        init(_ contribution: AchievementContribution) {
            earliest = contribution
            latest = contribution
        }

        mutating func register(_ contribution: AchievementContribution) {
            if Self.isEarlier(contribution, than: earliest) {
                earliest = contribution
            }
            if Self.isLater(contribution, than: latest) {
                latest = contribution
            }
        }

        private static func isEarlier(
            _ lhs: AchievementContribution,
            than rhs: AchievementContribution
        ) -> Bool {
            lhs.timestamp < rhs.timestamp
                || (lhs.timestamp == rhs.timestamp && lhs.scanID < rhs.scanID)
        }

        private static func isLater(
            _ lhs: AchievementContribution,
            than rhs: AchievementContribution
        ) -> Bool {
            lhs.timestamp > rhs.timestamp
                || (lhs.timestamp == rhs.timestamp && lhs.scanID > rhs.scanID)
        }
    }

    let type: AchievementType
    private var historiesBySpeciesKey: [String: SpeciesContributionHistory] = [:]
    private var lastInteractionDate: Date?

    init(type: AchievementType) {
        self.type = type
    }

    mutating func register(
        _ contribution: AchievementContribution,
        canonicalSpeciesKey: String
    ) {
        lastInteractionDate = max(lastInteractionDate ?? contribution.timestamp, contribution.timestamp)

        if historiesBySpeciesKey[canonicalSpeciesKey] == nil {
            historiesBySpeciesKey[canonicalSpeciesKey] = SpeciesContributionHistory(contribution)
        } else {
            historiesBySpeciesKey[canonicalSpeciesKey]?.register(contribution)
        }
    }

    var detailPayload: AchievementDetailPayload {
        // Select species by their first qualifying encounter so repeats cannot move
        // the unlock date or displace a species that originally earned the badge.
        let unlockingHistories = historiesBySpeciesKey.values.sorted { lhs, rhs in
            if lhs.earliest.timestamp == rhs.earliest.timestamp {
                return lhs.earliest.scanID < rhs.earliest.scanID
            }
            return lhs.earliest.timestamp < rhs.earliest.timestamp
        }
        
        let targetCount = type.definition.targetCount
        let cappedHistories = Array(unlockingHistories.prefix(targetCount))
        let unlockedAt = cappedHistories.count >= targetCount
            ? cappedHistories.last?.earliest.timestamp
            : nil
        
        // Detail rows remain useful and current by showing the newest scan for each
        // species that actually contributed to the unlock.
        let displayContributions = cappedHistories.map(\.latest).sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.scanID < rhs.scanID
            }
            return lhs.timestamp > rhs.timestamp
        }

        return AchievementDetailPayload(
            award: AwardPayload(
                type: type,
                currentCount: min(historiesBySpeciesKey.count, targetCount),
                lastInteractionDate: lastInteractionDate,
                unlockedAt: unlockedAt
            ),
            contributions: displayContributions
        )
    }
}
