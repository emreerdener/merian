import Combine
import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
enum InsightSheetTestSupport {
    static func createIsolatedContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let modelConfiguration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let context = ModelContext(container)
        ScanRepository.shared.configure(with: context)
        return context
    }

    static func contribution(
        kind: FieldTripScanContribution.SourceKind,
        sourceId: String,
        title: String
    ) -> FieldTripScanContribution {
        let isEvent = kind == .event
        return FieldTripScanContribution(
            sourceKind: kind,
            sourceId: sourceId,
            userFieldTripId: isEvent ? "linked-trip" : sourceId,
            participationId: isEvent ? sourceId : nil,
            templateId: "template-\(sourceId)",
            challengeId: isEvent ? "challenge-\(sourceId)" : nil,
            title: title,
            slug: title.lowercased().replacingOccurrences(of: " ", with: "_"),
            itemId: "item-\(sourceId)",
            prompt: isEvent ? "Bird" : "Butterfly or moth",
            levelNumber: 1,
            levelTitle: "Level 1",
            completedCount: isEvent ? 2 : 3,
            targetCount: isEvent ? 6 : 4,
            isComplete: false,
            artworkPrompt: isEvent ? "Bird" : "Butterfly or moth",
            artworkTemplateSlug: nil,
            destinationKind: isEvent ? "field_trip_challenge" : "field_trip",
            destinationTemplateId: isEvent ? nil : "template-\(sourceId)",
            destinationChecklistItemId: isEvent ? nil : "item-\(sourceId)",
            destinationChallengeId: isEvent ? "challenge-\(sourceId)" : nil
        )
    }

    static func biologicalEngine(scanId: String) -> InferenceEngine {
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: scanId,
            commonName: "Monarch",
            scientificName: "Danaus plexippus",
            insightData: InsightData(aiReasoning: "A butterfly.", hazardType: "none"),
            confidenceScore: 0.98,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )
        return engine
    }

    static func bindToolbarPresentation(
        _ viewModel: InsightSheetViewModel,
        scanId: String
    ) {
        let record = LocalScanRecord(
            id: scanId,
            speciesId: "toolbar_candidate_species",
            scientificName: "Uresiphita reversalis",
            commonName: "Genista Broom Moth"
        )
        viewModel.activeLocalRecord = record
        viewModel.activeLocalRecordId = record.id
        viewModel.toolbarRecordSnapshot =
            InsightToolbarRecordSnapshot(record: record)
    }

    static func milestoneTestSpecies(
        commonName: String = "Monarch Butterfly",
        isBiological: Bool = true
    ) -> SpeciesData {
        SpeciesData(
            scanId: "milestone_scan",
            commonName: commonName,
            scientificName: "Danaus plexippus",
            insightData: InsightData(aiReasoning: "Orange wings with black veins.", hazardType: "none"),
            confidenceScore: 0.97,
            isBiological: isBiological,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )
    }


    static func shareRecommendationViewModel(
        confidence: Double,
        inferenceTier: String?,
        userIdentificationOverride: String? = nil,
        userConfirmedIdentification: Bool = false
    ) -> InsightSheetViewModel {
        let viewModel = InsightSheetViewModel()
        let record = LocalScanRecord(
            speciesId: "share_recommendation_species",
            scientificName: "Rosa gallica",
            commonName: "French Rose",
            coverImagePath: "rose.webp"
        )
        viewModel.activeLocalRecord = record
        viewModel.activeLocalRecordId = record.id
        viewModel.toolbarRecordSnapshot = InsightToolbarRecordSnapshot(record: record)

        let engine = InferenceEngine()
        engine.activeMedia = ActiveScanMedia(items: [.image("rose.webp")])
        engine.speciesData = SpeciesData(
            scanId: record.id,
            commonName: "French Rose",
            scientificName: "Rosa gallica",
            insightData: InsightData(aiReasoning: "A rose with visible petals.", hazardType: "none"),
            confidenceScore: confidence,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild",
            inferenceTier: inferenceTier,
            userIdentificationOverride: userIdentificationOverride,
            userConfirmedIdentification: userConfirmedIdentification
        )
        viewModel.inferenceEngine = engine
        return viewModel
    }

}
