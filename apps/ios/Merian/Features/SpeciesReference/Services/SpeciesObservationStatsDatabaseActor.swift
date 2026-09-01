import SwiftData

@ModelActor
actor SpeciesObservationStatsDatabaseActor {
    func fetchLocalStats(
        scientificName: String,
        speciesId: String?,
        now: Date = Date()
    ) -> SpeciesObservationLocalStats {
        let normalizedName = SpeciesObservationStatsReducer
            .normalizedScientificName(scientificName)
        let targetSpeciesId = SpeciesObservationStatsReducer
            .normalizedSpeciesId(speciesId)
        var recordsById: [String: LocalScanRecord] = [:]

        if let targetSpeciesId {
            for record in fetchCandidates(matchingSpeciesId: targetSpeciesId) {
                recordsById[record.id] = record
            }
        }

        for record in fetchCandidates(matchingScientificName: normalizedName) {
            recordsById[record.id] = record
        }

        let records = recordsById.values.sorted {
            if $0.timestamp == $1.timestamp {
                return $0.id > $1.id
            }
            return $0.timestamp > $1.timestamp
        }

        return SpeciesObservationStatsReducer.reduceLocalStats(
            scientificName: normalizedName,
            speciesId: targetSpeciesId,
            records: records,
            now: now
        )
    }

    private func fetchCandidates(
        matchingSpeciesId speciesId: String
    ) -> [LocalScanRecord] {
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { record in
                record.isBiological == true &&
                    (record.speciesId == speciesId ||
                        record.confirmedSpeciesId == speciesId)
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.propertiesToFetch = Self.projectionProperties
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchCandidates(
        matchingScientificName scientificName: String
    ) -> [LocalScanRecord] {
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { record in
                record.isBiological == true &&
                    (record.scientificName == scientificName ||
                        record.userIdentificationOverride == scientificName)
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.propertiesToFetch = Self.projectionProperties
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private static let projectionProperties: [PartialKeyPath<LocalScanRecord>] = [
        \LocalScanRecord.id,
        \LocalScanRecord.speciesId,
        \LocalScanRecord.scientificName,
        \LocalScanRecord.userIdentificationOverride,
        \LocalScanRecord.confirmedSpeciesId,
        \LocalScanRecord.captureDate,
        \LocalScanRecord.timestamp,
        \LocalScanRecord.lifeStage,
        \LocalScanRecord.isBiological
    ]
}
