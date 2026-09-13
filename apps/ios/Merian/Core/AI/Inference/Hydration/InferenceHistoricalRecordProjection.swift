import Foundation

/// A value-only snapshot of the persisted fields needed to present and hydrate
/// one historical scan without retaining its SwiftData model across suspension.
struct InferenceHistoricalRecordProjection: Sendable {
    struct HydrationPlan: Equatable, Sendable {
        let allowsSpeciesHydration: Bool
        let allowsReferenceImages: Bool
        let shouldResetLocalLookalikes: Bool
        let needsWikipedia: Bool
        let needsMetadata: Bool
        let needsLookalikes: Bool

        var needsEnrichment: Bool {
            needsMetadata || needsLookalikes
        }
    }

    struct DeferredContent: Sendable {
        fileprivate let richLookalikes: SimilarSpecies?
        fileprivate let legacyLookalikeNames: [String]?
        fileprivate let candidatesData: Data?
    }

    struct DecodedContent: Sendable {
        let similarSpecies: SimilarSpecies?
        let candidates: [IdentificationCandidate]?
    }

    let scanId: String
    let displayedScientificName: String
    let overrideScientificName: String?
    let mediaSnapshot: CapturedMediaSnapshot
    let referenceImageURL: String?
    let gbifTaxonKey: Int?
    let speciesData: SpeciesData
    let hydrationPlan: HydrationPlan
    let deferredContent: DeferredContent

    @MainActor
    init(
        record: LocalScanRecord,
        resetLocalLookalikes: Bool
    ) {
        let allowsSpeciesHydration =
            record.hasResolvedBiologicalIdentification &&
            !record.isHumanSubject
        let allowsReferenceImages =
            allowsSpeciesHydration &&
            !record.shouldSuppressReferenceImages
        let shouldResetLocalLookalikes =
            allowsSpeciesHydration && resetLocalLookalikes
        let overrideScientificName = record.userIdentificationOverride
        let displayedScientificName =
            overrideScientificName ?? record.scientificName
        let displayedAIReasoning = overrideScientificName == nil
            ? (record.aiReasoning ?? "")
            : ""
        let richLookalikesData =
            allowsSpeciesHydration && !shouldResetLocalLookalikes
                ? record.lookalikesData
                : nil
        let legacyLookalikeNames =
            allowsSpeciesHydration && !shouldResetLocalLookalikes
                ? record.similarSpecies
                : nil
        let candidatesData = allowsSpeciesHydration
            ? record.candidatesData
            : nil
        let taxonomy = allowsSpeciesHydration
            ? TaxonomyData(
                kingdom: record.taxonomyKingdom,
                phylum: record.taxonomyPhylum,
                className: record.taxonomyClass,
                order: record.taxonomyOrder,
                family: record.taxonomyFamily,
                genus: record.taxonomyGenus
            )
            : nil
        let richLookalikes = richLookalikesData.flatMap {
            (try? JSONDecoder().decode([SimilarSpeciesEntry].self, from: $0))
                .map { SimilarSpecies(entries: $0) }
        }
        let lookalikesHaveNoCommonNames = richLookalikes.map {
            !$0.entries.isEmpty &&
                $0.entries.allSatisfy { $0.commonName == nil }
        } ?? false
        let needsMetadata = allowsSpeciesHydration && (
            record.habitatDescription?.trimmedNonEmptyValue == nil ||
                record.gbifTaxonKey == nil ||
                taxonomy?.hasUsableLookalikeValidation != true
        )
        let needsLookalikes = allowsSpeciesHydration && (
            shouldResetLocalLookalikes ||
                record.lookalikesData == nil ||
                lookalikesHaveNoCommonNames
        )
        let referenceImageURL = allowsReferenceImages
            ? record.referenceImageUrl
            : nil
        let needsWikipedia = allowsSpeciesHydration && (
            record.wikipediaOverview == nil ||
                (allowsReferenceImages &&
                    (record.referenceImageUrl?.isEmpty != false))
        )

        self.scanId = record.id
        self.displayedScientificName = displayedScientificName
        self.overrideScientificName = overrideScientificName
        self.mediaSnapshot = record.capturedMediaSnapshot
        self.referenceImageURL = referenceImageURL
        self.gbifTaxonKey = record.gbifTaxonKey
        self.hydrationPlan = HydrationPlan(
            allowsSpeciesHydration: allowsSpeciesHydration,
            allowsReferenceImages: allowsReferenceImages,
            shouldResetLocalLookalikes: shouldResetLocalLookalikes,
            needsWikipedia: needsWikipedia,
            needsMetadata: needsMetadata,
            needsLookalikes: needsLookalikes
        )
        self.deferredContent = DeferredContent(
            richLookalikes: richLookalikes,
            legacyLookalikeNames: legacyLookalikeNames,
            candidatesData: candidatesData
        )
        self.speciesData = SpeciesData(
            scanId: record.id,
            commonName: record.commonName,
            scientificName: displayedScientificName,
            insightData: InsightData(
                aiReasoning: displayedAIReasoning,
                hazardType: record.hazardType
            ),
            confidenceScore: record.confidenceScore ?? 0,
            blurScore: nil,
            similarSpecies: nil,
            wikipediaUrl: record.wikipediaUrl,
            wikipediaOverview: record.wikipediaOverview,
            referenceImageUrl: referenceImageURL,
            isBiological: record.isBiological,
            isLiveCapture: record.isLiveCapture,
            isInvasive: record.isInvasive,
            invasiveStatusRegion: record.invasiveStatusRegion,
            invasiveRationale: record.invasiveRationale,
            invasiveConfidence: record.invasiveConfidence,
            ecologyType: record.ecologyType,
            taxonomy: taxonomy,
            locationName: record.locationName,
            weatherCondition: record.weatherCondition,
            weatherTemperatureF: record.weatherTemperatureF,
            gpsElevation: record.gpsElevation,
            gpsLatitude: record.gpsLatitude,
            gpsLongitude: record.gpsLongitude,
            colors: nil,
            groupTags: nil,
            iucnRedListStatus: record.iucnRedListStatus,
            zoomFactor: record.zoomFactor,
            estimatedSizeCm: record.estimatedSizeCm,
            lifeStage: record.lifeStage,
            reproductiveCondition: record.reproductiveCondition,
            sex: record.sex,
            sexConfidence: record.sexConfidence,
            sexEvidence: record.sexEvidence,
            individualCount: record.individualCount,
            ecologicalInteractions: record.ecologicalInteractions,
            aiReasoning: record.aiReasoning,
            habitatDescription: record.habitatDescription,
            gbifTaxonKey: allowsSpeciesHydration
                ? record.gbifTaxonKey
                : nil,
            inferenceTier: record.inferenceTier,
            alternativeCommonNames: allowsSpeciesHydration
                ? record.alternativeCommonNames
                : nil,
            petIdentification: allowsSpeciesHydration
                ? record.petIdentification
                : nil,
            candidates: nil,
            imageQualityScore: record.imageQualityScore,
            aiScientificName: record.scientificName,
            userIdentificationOverride: overrideScientificName,
            userConfirmedIdentification: record.userConfirmedIdentification,
            isFlagged: record.isFlagged
        )
    }

    var referenceURLs: [String] {
        ExternalReferenceImagePolicy.allowedURLStrings(from: referenceImageURL)
    }

    static func decodeDeferredContent(
        _ content: DeferredContent
    ) async -> DecodedContent {
        await Task.detached(priority: .userInitiated) {
            let similarSpecies = content.richLookalikes
                ?? content.legacyLookalikeNames.flatMap { names in
                    names.isEmpty
                        ? nil
                        : SimilarSpecies(
                            entries: names.map {
                                SimilarSpeciesEntry(
                                    scientificName: $0,
                                    commonName: nil,
                                    referenceImageUrl: nil,
                                    iucnRedListStatus: nil
                                )
                            }
                        )
                }
            let candidates = content.candidatesData.flatMap {
                try? JSONDecoder().decode(
                    [IdentificationCandidate].self,
                    from: $0
                )
            }
            return DecodedContent(
                similarSpecies: similarSpecies,
                candidates: candidates
            )
        }.value
    }
}
