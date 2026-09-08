import Foundation
import SwiftData

extension BackgroundDatabaseActor {
    // MARK: - Wikipedia Enrichment

    /// Retroactively hydrates a scan record with Wikipedia data post-inference.
    @discardableResult
    func updateScanWithWikipedia(
        scanId: String,
        extract: String?,
        url: String?,
        imageUrl: String?,
        expectedScientificName: String? = nil
    ) -> Bool {
        var descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let record: LocalScanRecord?
        do {
            record = try modelContext.fetch(descriptor).first
        } catch {
            MerianLog.data.debug("updateScanWithWikipedia: fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)")
            return false
        }
        guard let record else { return false }

        let trimmedOverride = record.userIdentificationOverride?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveScientificName = if let trimmedOverride,
                                         !trimmedOverride.isEmpty {
            trimmedOverride
        } else {
            record.scientificName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        }
        guard expectedScientificName.map({
            effectiveScientificName.caseInsensitiveCompare($0) == .orderedSame
        }) ?? true else {
            return false
        }

        var didChange = false
        if let extract, record.wikipediaOverview != extract {
            record.wikipediaOverview = extract
            didChange = true
        }
        if let url, record.wikipediaUrl != url {
            record.wikipediaUrl = url
            didChange = true
        }
        if let imageUrl, !imageUrl.isEmpty {
            let sanitizedImageUrl = ExternalReferenceImagePolicy.sanitizedURLList(
                imageUrl
            )
            if record.referenceImageUrl != sanitizedImageUrl {
                record.referenceImageUrl = sanitizedImageUrl
                didChange = true
            }
        }
        guard didChange else { return false }

        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            MerianLog.data.error("updateScanWithWikipedia: save failed for \(scanId, privacy: .private): \(error, privacy: .private)")
            return false
        }
    }

    // MARK: - Record Mutation

    /// Fetches a single `LocalScanRecord` by ID, applies `mutation`, and saves.
    /// All point-update methods below delegate here to keep fetch-mutate-save DRY.
    private func mutateScan(
        id: String,
        expectedScientificName: String? = nil,
        mutation: (LocalScanRecord) -> Void
    ) {
        var descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try? modelContext.fetch(descriptor).first,
              expectedScientificName.map({
                  record.scientificName.caseInsensitiveCompare($0)
                      == .orderedSame
              }) ?? true else {
            return
        }
        mutation(record)
        do { try modelContext.save() } catch {
            modelContext.rollback()
            MerianLog.data.error("mutateScan: save failed for \(id, privacy: .private): \(error, privacy: .private)")
        }
    }

    // MARK: - Species Enrichment

    /// Patches a scan record with post-inference enrichment data from the `enrich-scan` Edge function.
    /// Each parameter is optional — callers pass only the fields their scope resolved, nil fields are skipped.
    func updateScanWithEnrichment(
        scanId: String,
        habitatDescription: String?,
        gbifTaxonKey: Int?,
        similarSpeciesJsonData: Data?,
        taxonomy: EdgeResponse.Taxonomy?,
        alternativeCommonNames: [String]? = nil,
        expectedScientificName: String? = nil
    ) {
        mutateScan(
            id: scanId,
            expectedScientificName: expectedScientificName
        ) { record in
            if let habitat = habitatDescription { record.habitatDescription = habitat }
            if let key = gbifTaxonKey { record.gbifTaxonKey = key }
            if let jsonData = similarSpeciesJsonData { record.lookalikesData = jsonData }
            if let tax = taxonomy {
                record.taxonomyKingdom = tax.kingdom
                record.taxonomyPhylum = tax.phylum
                record.taxonomyClass = tax.`class`
                record.taxonomyOrder = tax.order
                record.taxonomyFamily = tax.family
                record.taxonomyGenus = tax.genus
            }
            if let names = alternativeCommonNames { record.alternativeCommonNames = names }
        }
    }

    /// One-time recovery path for stale similar-species caches written before the backend
    /// began enforcing validated taxonomy. Clearing both the rich blob and legacy flat
    /// array forces future scan opens to rehydrate from the server under the new rules.
    func clearAllLocalLookalikesCache() {
        let batchSize = 200

        while true {
            var descriptor = FetchDescriptor<LocalScanRecord>(
                predicate: #Predicate {
                    $0.isBiological == true &&
                    ($0.lookalikesData != nil || $0.similarSpecies != nil)
                },
                sortBy: [SortDescriptor(\.timestamp)]
            )
            descriptor.fetchLimit = batchSize

            let records: [LocalScanRecord]
            do {
                records = try modelContext.fetch(descriptor)
            } catch {
                MerianLog.data.error("clearAllLocalLookalikesCache: fetch failed: \(error, privacy: .private)")
                return
            }

            guard !records.isEmpty else { return }

            for record in records {
                record.lookalikesData = nil
                record.similarSpecies = nil
            }

            do {
                try modelContext.save()
            } catch {
                modelContext.rollback()
                MerianLog.data.error("clearAllLocalLookalikesCache: save failed: \(error, privacy: .private)")
                return
            }
        }
    }

    // MARK: - Identification Override Persistence

    /// Atomically admits a new local override before asynchronous dictionary
    /// hydration. A crash can therefore leave either the prior AI identity or
    /// a complete override placeholder, never fields from both species.
    func beginScanIdentificationOverride(
        scanId: String,
        scientificName: String
    ) {
        mutateScan(id: scanId) { record in
            record.userIdentificationOverride = scientificName
            record.userConfirmedIdentification = false
            record.confirmedSpeciesId = nil
            record.userReviewState = .userOverridden
            record.isFlagged = false
            replaceIdentificationPresentation(
                on: record,
                commonName: scientificName
            )
        }
    }

    /// Persists the user's identification review action to the local SwiftData store.
    /// - Parameters:
    ///   - scanId: The scan record to update.
    ///   - override: The scientific name the user selected, or nil to clear.
    ///   - newConfirmedSpeciesId: The definitive species UUID (either the AI original or an override candidate).
    func updateScanWithOverride(
        scanId: String,
        override: String?,
        confirmed: Bool,
        newConfirmedSpeciesId: String?,
        userReviewState: UserReviewState
    ) {
        mutateScan(id: scanId) { record in
            // Snapshot the original AI identity before mutating any SwiftData-backed
            // review fields. The reset placeholder must not depend on a managed
            // accessor after the record has begun changing.
            let resetCommonName = userReviewState == .unreviewed
                ? record.scientificName
                : nil
            record.userIdentificationOverride = override
            record.userConfirmedIdentification = confirmed
            record.confirmedSpeciesId = newConfirmedSpeciesId
            record.userReviewState = userReviewState

            guard let resetCommonName else { return }
            replaceIdentificationPresentation(
                on: record,
                commonName: resetCommonName
            )
        }
    }

    private func replaceIdentificationPresentation(
        on record: LocalScanRecord,
        commonName: String
    ) {
        record.commonName = commonName
        record.hazardType = "none"
        record.wikipediaOverview = nil
        record.wikipediaUrl = nil
        record.referenceImageUrl = nil
        record.iucnRedListStatus = nil
        record.habitatDescription = nil
        record.gbifTaxonKey = nil
        record.taxonomyKingdom = nil
        record.taxonomyPhylum = nil
        record.taxonomyClass = nil
        record.taxonomyOrder = nil
        record.taxonomyFamily = nil
        record.taxonomyGenus = nil
        record.similarSpecies = nil
        record.lookalikesData = nil
        record.alternativeCommonNames = nil
    }

    /// Persists the species-dictionary data fetched for an identification override or reset,
    /// so the corrected species fields survive sheet dismissal and reopen.
    ///
    /// `scientificName` is deliberately excluded — that column is preserved as the authoritative
    /// original-AI identifier and is reused as `aiScientificName` on `load(from:)`. This allows
    /// `resetIdentificationReview` to recover the original name without a separate schema field.
    /// `replacingSpeciesIdentity` must be true only for an interactive override/reset; a
    /// historical refresh of the already-active override preserves valid sparse-row fallbacks.
    func updateScanWithOverrideSpeciesData(
        scanId: String,
        commonName: String,
        hazardType: String,
        wikipediaOverview: String?,
        wikipediaUrl: String?,
        referenceImageUrl: String?,
        iucnRedListStatus: String?,
        habitatDescription: String?,
        gbifTaxonKey: Int?,
        taxonomy: TaxonomyData?,
        replacingSpeciesIdentity: Bool
    ) {
        mutateScan(id: scanId) { record in
            record.commonName = commonName
            record.hazardType = hazardType
            record.wikipediaOverview = wikipediaOverview
            record.wikipediaUrl = wikipediaUrl
            record.referenceImageUrl = ExternalReferenceImagePolicy.sanitizedURLList(
                referenceImageUrl
            )
            record.iucnRedListStatus = iucnRedListStatus
            record.habitatDescription = habitatDescription
            record.gbifTaxonKey = gbifTaxonKey
            if let taxonomy {
                record.taxonomyKingdom = taxonomy.kingdom
                record.taxonomyPhylum = taxonomy.phylum
                record.taxonomyClass = taxonomy.className
                record.taxonomyOrder = taxonomy.order
                record.taxonomyFamily = taxonomy.family
                record.taxonomyGenus = taxonomy.genus
            } else if replacingSpeciesIdentity {
                record.taxonomyKingdom = nil
                record.taxonomyPhylum = nil
                record.taxonomyClass = nil
                record.taxonomyOrder = nil
                record.taxonomyFamily = nil
                record.taxonomyGenus = nil
            }
            if replacingSpeciesIdentity {
                record.similarSpecies = nil
                record.lookalikesData = nil
                record.alternativeCommonNames = nil
            }
        }
    }

    /// Clears legacy manual-review state when an identification is changed or reset.
    func updateScanAsUnflagged(scanId: String) {
        mutateScan(id: scanId) { $0.isFlagged = false }
    }
}
