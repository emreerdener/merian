import Foundation

struct ScanMilestoneIdentity: Equatable, Sendable {
    let value: String
    let key: String
}

enum ScanMilestonePolicy {
    static func identity(for scanID: String) -> ScanMilestoneIdentity? {
        let value = scanID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return ScanMilestoneIdentity(value: value, key: value.lowercased())
    }

    static func milestones(
        from result: FieldTripProgressResult?
    ) -> [FieldTripMilestonePayload] {
        guard let result else { return [] }

        return result.fieldTripUpdates.compactMap(
            FieldTripMilestonePayload.standard
        ) + result.challengeUpdates.compactMap(
            FieldTripMilestonePayload.challenge
        )
    }

    static func isValidNewToMerianMilestone(_ data: SpeciesData) -> Bool {
        let lowerName = data.commonName.lowercased()
        return data.isNewToMerianDictionary
            && data.isBiological
            && lowerName != "not applicable"
            && lowerName != "unknown subject"
            && lowerName != "inanimate object"
    }
}
