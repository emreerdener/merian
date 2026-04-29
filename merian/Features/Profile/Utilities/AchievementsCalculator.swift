import Foundation

protocol AchievementRecordRepresentable {
    var id: String { get }
    var scientificName: String { get }
    var timestamp: Date { get }
    var taxonomyKingdom: String? { get }
    var taxonomyClass: String? { get }
    var ecologyType: String { get }
    var weatherTemperatureF: Double? { get }
    var gpsElevation: Double? { get }
    var isInvasive: Bool { get }
    var iucnRedListStatus: String? { get }
    var hazardType: String { get }
    var confidenceScore: Double? { get }
}

extension LocalScanRecord: AchievementRecordRepresentable {}

struct AchievementsCalculator {
    static func calculate<Record: AchievementRecordRepresentable>(from allRecords: [Record]) -> [AwardPayload] {
        evaluations(from: allRecords).map(\.award)
    }

    static func detail<Record: AchievementRecordRepresentable>(
        for type: String,
        from allRecords: [Record]
    ) -> AchievementDetailPayload? {
        evaluations(from: allRecords).first { $0.award.type == type }
    }

    private static func evaluations<Record: AchievementRecordRepresentable>(
        from allRecords: [Record]
    ) -> [AchievementDetailPayload] {
        var explorer = AchievementAccumulator(
            title: "The Naturalist",
            type: "explorer",
            targetCount: 5
        )
        var plants = AchievementAccumulator(
            title: "The Botanist",
            type: "plantae",
            targetCount: 10
        )
        var insects = AchievementAccumulator(
            title: "The Zoologist",
            type: "insecta",
            targetCount: 10
        )
        var fungi = AchievementAccumulator(
            title: "The Mycologist",
            type: "fungi",
            targetCount: 10
        )
        var urban = AchievementAccumulator(
            title: "The Urban Ecologist",
            type: "urban",
            targetCount: 10
        )
        var frostWalker = AchievementAccumulator(
            title: "The Frost Walker",
            type: "frost_walker",
            targetCount: 5
        )
        var alpine = AchievementAccumulator(
            title: "The Alpine Naturalist",
            type: "alpine",
            targetCount: 5
        )
        var nocturnal = AchievementAccumulator(
            title: "The Nocturnal Observer",
            type: "nocturnal",
            targetCount: 10
        )
        var guardian = AchievementAccumulator(
            title: "The Guardian",
            type: "guardian",
            targetCount: 5
        )
        var conservationist = AchievementAccumulator(
            title: "The Conservationist",
            type: "conservationist",
            targetCount: 1
        )
        var toxicologist = AchievementAccumulator(
            title: "The Toxicologist",
            type: "toxicologist",
            targetCount: 5
        )
        var perfectLens = AchievementAccumulator(
            title: "The Perfect Lens",
            type: "perfect_lens",
            targetCount: 25
        )

        for record in allRecords {
            explorer.register(record, reasonText: "Unique species documented")

            if let kingdom = record.taxonomyKingdom?.lowercased() {
                if kingdom == "fungi" {
                    fungi.register(record, reasonText: "Fungi kingdom")
                } else if kingdom == "plantae" {
                    plants.register(record, reasonText: "Plant kingdom")
                }
            }

            if let className = record.taxonomyClass?.lowercased() {
                if className == "insecta" || className == "arachnida" {
                    insects.register(record, reasonText: className.capitalized)
                }
            }

            let ecology = record.ecologyType.lowercased()
            if ecology == "urban" || ecology == "domesticated" {
                urban.register(record, reasonText: ecology.capitalized + " ecology")
            }

            if let temp = record.weatherTemperatureF, temp < 32.0 {
                frostWalker.register(record, reasonText: "\(Int(temp.rounded()))°F capture")
            }
            if let elevation = record.gpsElevation, elevation > 2500.0 {
                alpine.register(record, reasonText: "\(Int(elevation.rounded())) m elevation")
            }

            let hour = Calendar.current.component(.hour, from: record.timestamp)
            if hour >= 22 || hour <= 5 {
                nocturnal.register(record, reasonText: "Captured after dark")
            }
            if record.isInvasive {
                guardian.register(record, reasonText: "Marked invasive")
            }
            if let status = record.iucnRedListStatus,
               !status.isEmpty,
               status != "LC",
               status != "NE",
               status != "DD" {
                conservationist.register(record, reasonText: "IUCN \(status)")
            }
            if record.hazardType != "none" {
                toxicologist.register(
                    record,
                    reasonText: record.hazardType
                        .replacingOccurrences(of: "_", with: " ")
                        .capitalized
                )
            }
            if let score = record.confidenceScore, score >= 0.98 {
                perfectLens.register(record, reasonText: "\(Int((score * 100).rounded()))% AI confidence")
            }
        }

        let firstScanContribution = allRecords.last.map {
            AchievementContribution(
                id: $0.id,
                scientificName: $0.scientificName,
                timestamp: $0.timestamp,
                reasonText: "Your first recorded scan"
            )
        }
        let firstScanDate = firstScanContribution?.timestamp
        let firstScanDetail = AchievementDetailPayload(
            award: AwardPayload(
                title: "The Observer",
                type: "first_scan",
                currentCount: allRecords.isEmpty ? 0 : 1,
                targetCount: 1,
                lastInteractionDate: firstScanDate
            ),
            contributions: firstScanContribution.map { [$0] } ?? []
        )

        return [
            firstScanDetail,
            explorer.detailPayload,
            plants.detailPayload,
            insects.detailPayload,
            fungi.detailPayload,
            urban.detailPayload,
            frostWalker.detailPayload,
            alpine.detailPayload,
            nocturnal.detailPayload,
            guardian.detailPayload,
            conservationist.detailPayload,
            toxicologist.detailPayload,
            perfectLens.detailPayload
        ]
    }
}

private struct AchievementAccumulator {
    let title: String
    let type: String
    let targetCount: Int
    private var uniqueSpecies = Set<String>()
    private var lastInteractionDate: Date?
    private var contributions: [AchievementContribution] = []

    init(title: String, type: String, targetCount: Int) {
        self.title = title
        self.type = type
        self.targetCount = targetCount
    }

    mutating func register<Record: AchievementRecordRepresentable>(
        _ record: Record,
        reasonText: String
    ) {
        guard uniqueSpecies.insert(record.scientificName).inserted else { return }
        lastInteractionDate = lastInteractionDate ?? record.timestamp
        contributions.append(
            AchievementContribution(
                id: record.id,
                scientificName: record.scientificName,
                timestamp: record.timestamp,
                reasonText: reasonText
            )
        )
    }

    var detailPayload: AchievementDetailPayload {
        AchievementDetailPayload(
            award: AwardPayload(
                title: title,
                type: type,
                currentCount: uniqueSpecies.count,
                targetCount: targetCount,
                lastInteractionDate: lastInteractionDate
            ),
            contributions: contributions
        )
    }
}
