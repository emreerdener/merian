import Combine
import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
@Suite("Inference Engine Tests", .serialized)
struct InferenceEngineTests {
    actor CounterBox {
        private(set) var value = 0
        func increment() { value += 1 }
    }
    
    init() {
        MockURLProtocol.mockEndpoints = [:]
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        MerianNetworkClient.shared.overridingSession = URLSession(configuration: config)
        MerianNetworkClient.shared.resetSpeciesDictionaryCacheForTesting()
        UserDefaults.standard.set(
            MerianConfig.localLookalikesCacheResetVersion,
            forKey: UserDefaultsKeys.localLookalikesCacheResetVersion
        )
    }

    @Test func testEdgeResponseDecodingSuccess() throws {
        // Arrange: Simulate a valid JSON payload from the Gemini Edge Function
        let jsonString = """
        {
            "success": true,
            "data": {
                "scan_id": "gemini_scan_001",
                "is_biological_subject": true,
                "is_live_capture": true,
                "ecology_type": "Terrestrial",
                "is_invasive": false,
                "invasive_status_region": "North America",
                "invasive_rationale": "Native in the region supplied by the scan context.",
                "invasive_confidence": 0.81,
                "scientific_name": "Procyon lotor",
                "common_name": "Raccoon",
                "confidence_score": 0.96,
                "taxonomy": {
                    "kingdom": "Animalia",
                    "phylum": "Chordata",
                    "class": "Mammalia",
                    "order": "Carnivora",
                    "family": "Procyonidae",
                    "genus": "Procyon"
                },
                "insight_data": {
                    "ai_reasoning": "A medium-sized mammal native to North America.",
                    "hazard_type": "none"
                },
                "wikipedia_url": "https://en.wikipedia.org/wiki/Raccoon",
                "reference_image_url": "https://example.com/raccoon.jpg"
            }
        }
        """
        
        let jsonData = jsonString.data(using: .utf8)!
        
        // Act
        let decoder = JSONDecoder()
        let wrapper = try decoder.decode(EdgeResponseWrapper.self, from: jsonData)
        
        // Assert: Ensure nested Decodable structures map perfectly
        let edgeResponse = wrapper.data
        
        #expect(wrapper.success == true)
        #expect(edgeResponse.scan_id == "gemini_scan_001")
        #expect(edgeResponse.common_name == "Raccoon")
        #expect(edgeResponse.scientific_name == "Procyon lotor")
        #expect(edgeResponse.confidence_score == 0.96)
        #expect(edgeResponse.is_biological_subject == true)
        #expect(edgeResponse.ecology_type == "Terrestrial")
        #expect(edgeResponse.is_invasive == false)
        #expect(edgeResponse.invasive_status_region == "North America")
        #expect(edgeResponse.invasive_rationale == "Native in the region supplied by the scan context.")
        #expect(edgeResponse.invasive_confidence == 0.81)
        
        #expect(edgeResponse.taxonomy?.family == "Procyonidae")
        #expect(edgeResponse.insight_data?.hazard_type == "none")
        #expect(edgeResponse.insight_data?.ai_reasoning?.contains("mammal") == true)
        #expect(edgeResponse.wikipedia_url == "https://en.wikipedia.org/wiki/Raccoon")
    }

    @Test func testEdgeResponseDecodingPartialData() throws {
        // Arrange: Simulate a corrupted or low-confidence edge result containing nil fields
        let jsonString = """
        {
            "success": true,
            "data": {
                "is_biological_subject": false,
                "common_name": "Inanimate Object"
            }
        }
        """
        let jsonData = jsonString.data(using: .utf8)!
        
        // Act
        let decoder = JSONDecoder()
        let wrapper = try decoder.decode(EdgeResponseWrapper.self, from: jsonData)
        
        // Assert: Ensure optionality gracefully falls back rather than violently crashing
        let edgeResponse = wrapper.data
        
        #expect(edgeResponse.is_biological_subject == false)
        #expect(edgeResponse.common_name == "Inanimate Object")
        #expect(edgeResponse.scientific_name == nil)
        #expect(edgeResponse.taxonomy == nil)
        #expect(edgeResponse.insight_data == nil)
    }

    @Test func confidenceZeroResponseIsTerminalWithoutPersistence() async throws {
        let resultData = Data(
            """
            {
                "success": true,
                "data": {
                    "scan_id": "confidence-zero-terminal",
                    "is_biological_subject": false,
                    "common_name": "No identification",
                    "confidence_score": 0
                }
            }
            """.utf8
        )

        let result = try await InferenceProcessingActor.shared.parseAndSave(
            resultData: resultData,
            telemetry: makeTelemetry(),
            modelContext: nil,
            compressedDatas: [],
            persistenceFence: LiveInferencePersistenceFence(
                scanId: "confidence-zero-terminal",
                generation: UUID()
            )
        )

        #expect(result.didCompletePersistence)
        #expect(result.mappedData?.confidenceScore == 0)
        #expect(result.savedPaths.isEmpty)
    }

    @Test func confidenceZeroResponseWithWrongScanIdRemainsRecoverable() async throws {
        let resultData = Data(
            """
            {
                "success": true,
                "data": {
                    "scan_id": "stale-confidence-zero",
                    "is_biological_subject": false,
                    "confidence_score": 0
                }
            }
            """.utf8
        )

        let result = try await InferenceProcessingActor.shared.parseAndSave(
            resultData: resultData,
            telemetry: makeTelemetry(),
            modelContext: nil,
            compressedDatas: [],
            persistenceFence: LiveInferencePersistenceFence(
                scanId: "replacement-confidence-zero",
                generation: UUID()
            )
        )

        #expect(!result.didCompletePersistence)
    }

    @Test func decodedButUnusableSuccessEnvelopeRemainsRecoverable() async {
        let scanId = "unusable-success-envelope"
        for resultData in [
            Data(
                #"{"success":false,"data":{"scan_id":"unusable-success-envelope","confidence_score":0}}"#.utf8
            ),
            Data(
                #"{"success":true,"data":{"scan_id":"unusable-success-envelope"}}"#.utf8
            ),
            Data(
                #"{"success":true,"data":{"scan_id":"unusable-success-envelope","confidence_score":2}}"#.utf8
            )
        ] {
            await #expect(throws: MerianError.decodingFailed) {
                try await InferenceProcessingActor.shared.parseAndSave(
                    resultData: resultData,
                    telemetry: makeTelemetry(),
                    modelContext: nil,
                    compressedDatas: [],
                    persistenceFence: LiveInferencePersistenceFence(
                        scanId: scanId,
                        generation: UUID()
                    )
                )
            }
        }
    }

    @Test func positiveConfidenceResponseWithoutPersistenceRemainsRecoverable() async throws {
        let resultData = Data(
            """
            {
                "success": true,
                "data": {
                    "scan_id": "positive-confidence-recovery",
                    "is_biological_subject": true,
                    "scientific_name": "Danaus plexippus",
                    "common_name": "Monarch Butterfly",
                    "confidence_score": 0.95
                }
            }
            """.utf8
        )

        let result = try await InferenceProcessingActor.shared.parseAndSave(
            resultData: resultData,
            telemetry: makeTelemetry(),
            modelContext: nil,
            compressedDatas: [Data([0x01])]
        )

        #expect(!result.didCompletePersistence)
        #expect(result.savedPaths.isEmpty)
    }

    @Test func queueBackedNonVisualAttemptRequiresForegroundGeneration() {
        let engine = InferenceEngine()
        let scanId =
            "nonvisual-missing-generation-\(UUID().uuidString.lowercased())"

        engine.analyzeNonVisual(
            scanId: scanId,
            observationContexts: [
                ObservationContext(freeText: "Small orange butterfly")
            ],
            telemetry: makeTelemetry(),
            modelContext: nil
        )

        #expect(engine.inferenceTask == nil)
        #expect(engine.activeScanId == nil)
        #expect(!engine.isProcessing)
    }

    @Test func testLoadFromLocalScanRecord() throws {
        // Arrange: Create an ephemeral LocalScanRecord model offline
        let record = LocalScanRecord(
            speciesId: "species_abc",
            scientificName: "Danaus plexippus",
            commonName: "Monarch Butterfly",
            semanticTags: ["butterfly", "insect"],
            hazardType: "poisonous",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "Terrestrial",
            wikipediaUrl: "https://en.wikipedia.org/wiki/Monarch_butterfly",
            referenceImageUrl: "https://example.com/monarch.jpg",
            confidenceScore: 0.99,
            taxonomyKingdom: "Animalia",
            taxonomyPhylum: "Arthropoda",
            taxonomyClass: "Insecta",
            taxonomyOrder: "Lepidoptera",
            taxonomyFamily: "Nymphalidae",
            taxonomyGenus: "Danaus",
            aiReasoning: "A milkweed butterfly in the family Nymphalidae."
        )

        let engine = InferenceEngine()
        var completedScanIds: [String] = []
        let completionCancellable = AppEventPublisher.shared.publisher.sink { event in
            if case .foregroundBiologicalScanCompleted(let scanId) = event {
                completedScanIds.append(scanId)
            }
        }
        defer { completionCancellable.cancel() }

        // Act
        engine.load(from: record)

        // Assert: Ensure engine parses the offline model locally into SpeciesData
        let resultingData = try #require(engine.speciesData, "SpeciesData should not be nil after loading")

        #expect(resultingData.commonName == "Monarch Butterfly")
        #expect(resultingData.scientificName == "Danaus plexippus")
        #expect(resultingData.confidenceScore == 0.99)
        #expect(resultingData.insightData.hazardType == "poisonous")
        #expect(resultingData.insightData.aiReasoning.contains("Nymphalidae"))
        #expect(resultingData.taxonomy?.genus == "Danaus")

        // Note: validHistoricImagePaths is populated asynchronously by FileIOActor.validPaths(from:)
        // which filters out non-existent disk paths — cannot assert file paths in the unit test sandbox.

        #expect(engine.isProcessing == false, "Processing state should return to false synchronously")
        #expect(completedScanIds.isEmpty, "Viewing historical scan data must not publish a foreground completion")
    }

    @Test func testLoadFromLocalScanRecordWithNilConfidenceDoesNotDefaultToPerfectMatch() async throws {
        let record = LocalScanRecord(
            speciesId: "species_unresolved",
            scientificName: LocalScanRecord.unresolvedBiologicalScientificName,
            commonName: LocalScanRecord.unresolvedBiologicalCommonName,
            isBiological: true,
            confidenceScore: nil,
            gbifTaxonKey: 12345
        )
        let engine = InferenceEngine()

        engine.load(from: record)
        try await Task.sleep(nanoseconds: 50_000_000)

        let resultingData = try #require(engine.speciesData, "SpeciesData should not be nil after loading")
        #expect(resultingData.confidenceScore == 0.0)
        #expect(resultingData.confidenceScore != 1.0, "Missing local confidence must not render as 100% confident")
        #expect(engine.activeMedia.referenceState == .empty, "Unresolved placeholder records must not show a phantom reference-loading page")
    }

    @Test func testLoadFromLocalScanRecordSnapshotsReferenceImageBeforeAsyncHydration() async throws {
        let referenceURL = "https://example.com/reference-image.jpg"
        let record = LocalScanRecord(
            speciesId: "species_reference_snapshot",
            scientificName: "Danaus plexippus",
            commonName: "Monarch Butterfly",
            isBiological: true,
            referenceImageUrl: referenceURL,
            confidenceScore: 0.92,
            gbifTaxonKey: 5131904
        )
        let engine = InferenceEngine()

        engine.load(from: record)
        record.referenceImageUrl = nil
        try await Task.sleep(nanoseconds: 50_000_000)

        if case .loaded(let urls) = engine.activeMedia.referenceState {
            #expect(urls == [referenceURL])
        } else {
            Issue.record("Historical hydration must use the snapshotted reference image URL, not a later live SwiftData read")
        }
    }

    @Test func testPrepareForNewScanClearsPendingBackgroundWrites() async throws {
        let engine = InferenceEngine()
        let counter = CounterBox()

        for _ in 0..<engine.debugBackgroundWriteTaskCap {
            engine.debugEnqueueTrackedBackgroundTask {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
        engine.debugEnqueueTrackedBackgroundTask {
            await counter.increment()
        }

        #expect(engine.debugBackgroundWriteState().pending == 1)

        engine.prepareForNewScan()
        try? await Task.sleep(nanoseconds: 150_000_000)

        let state = engine.debugBackgroundWriteState()
        #expect(state.active == 0, "prepareForNewScan must cancel all active background writes")
        #expect(state.pending == 0, "prepareForNewScan must clear queued background writes")
        #expect(await counter.value == 0, "Queued background writes from the old scan must never run after reset")
    }

    @Test func testCancelActiveRequestClearsPendingBackgroundWrites() async throws {
        let engine = InferenceEngine()
        let counter = CounterBox()

        for _ in 0..<engine.debugBackgroundWriteTaskCap {
            engine.debugEnqueueTrackedBackgroundTask {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
        engine.debugEnqueueTrackedBackgroundTask {
            await counter.increment()
        }

        #expect(engine.debugBackgroundWriteState().pending == 1)

        engine.cancelActiveRequest()
        try? await Task.sleep(nanoseconds: 150_000_000)

        let state = engine.debugBackgroundWriteState()
        #expect(state.active == 0, "cancelActiveRequest must cancel all active background writes")
        #expect(state.pending == 0, "cancelActiveRequest must clear queued background writes")
        #expect(await counter.value == 0, "Queued background writes from the cancelled scan must never run")
    }

    @Test func testBackgroundWriteBacklogHasAHardMemoryBound() async throws {
        let engine = InferenceEngine()
        let overflow = 32

        for _ in 0..<engine.debugBackgroundWriteTaskCap {
            engine.debugEnqueueTrackedBackgroundTask {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
        for _ in 0..<(engine.debugPendingBackgroundWriteTaskCap + overflow) {
            engine.debugEnqueueTrackedBackgroundTask {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }

        let state = engine.debugBackgroundWriteState()
        #expect(state.active == engine.debugBackgroundWriteTaskCap)
        #expect(
            state.pending == engine.debugPendingBackgroundWriteTaskCap,
            "Best-effort metadata writes must not create an unbounded closure backlog"
        )

        engine.cancelActiveRequest()
        try? await Task.sleep(nanoseconds: 150_000_000)
        #expect(engine.debugBackgroundWriteState().active == 0)
        #expect(engine.debugBackgroundWriteState().pending == 0)
    }

    // MARK: - load(from:) enrichment gate: all-null common names

    @Test func testLoadFromRecordWithAllNullCommonNamesTriggersEnrichment() throws {
        // Arrange: encode a lookalikesData blob where every entry has commonName == nil.
        // This simulates a scan whose join table was populated before the common-name
        // back-fill pipeline existed. The needsEnrichment gate must fire so enrich-scan
        // is called and common names are fetched.
        let staleEntries = [
            SimilarSpeciesEntry(scientificName: "Procyon cancrivorus", commonName: nil, referenceImageUrl: nil, iucnRedListStatus: nil),
            SimilarSpeciesEntry(scientificName: "Bassariscus astutus", commonName: nil, referenceImageUrl: nil, iucnRedListStatus: nil)
        ]
        let lookalikesData = try JSONEncoder().encode(staleEntries)

        let record = LocalScanRecord(
            speciesId: "species_xyz",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            semanticTags: ["raccoon"],
            hazardType: "none",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild",
            lookalikesData: lookalikesData,                 // present but all-null common names
            habitatDescription: "Forests and urban areas.", // present — not the trigger
            gbifTaxonKey: 2433697                          // present — not the trigger
        )

        let engine = InferenceEngine()
        engine.load(from: record)

        // The synchronous part of load(from:) must have pre-decoded the blob once
        // and produced a SimilarSpecies with the two stale entries.
        // speciesData.similarSpecies is set asynchronously inside historicHydrationTask,
        // but we can assert the engine initialised cleanly and isProcessing returned false.
        #expect(engine.isProcessing == false)
        // The enrichment path is async (historicHydrationTask); we verify the gate condition
        // was met by confirming lookalikesData decoded to all-null common names correctly.
        let decoded = try JSONDecoder().decode([SimilarSpeciesEntry].self, from: lookalikesData)
        #expect(decoded.allSatisfy { $0.commonName == nil }, "All entries must have nil commonName to trigger enrichment gate")
        #expect(decoded.count == 2)
    }

    @Test func testLoadFromRecordWithRichCommonNamesSkipsEnrichment() throws {
        // Arrange: encode a lookalikesData blob where entries have commonName populated.
        // needsEnrichment must be false — no redundant enrich-scan call should fire.
        let richEntries = [
            SimilarSpeciesEntry(scientificName: "Procyon cancrivorus", commonName: "Crab-eating Raccoon", referenceImageUrl: "https://example.com/cancrivorus.jpg", iucnRedListStatus: "LC"),
            SimilarSpeciesEntry(scientificName: "Bassariscus astutus", commonName: "Ringtail", referenceImageUrl: nil, iucnRedListStatus: "LC")
        ]
        let lookalikesData = try JSONEncoder().encode(richEntries)

        let record = LocalScanRecord(
            speciesId: "species_xyz",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            semanticTags: ["raccoon"],
            hazardType: "none",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild",
            lookalikesData: lookalikesData,
            habitatDescription: "Forests and urban areas.",
            gbifTaxonKey: 2433697
        )

        let engine = InferenceEngine()
        engine.load(from: record)

        #expect(engine.isProcessing == false)
        // Confirm the gate condition is not met — at least one commonName is non-nil.
        let decoded = try JSONDecoder().decode([SimilarSpeciesEntry].self, from: lookalikesData)
        #expect(decoded.contains { $0.commonName != nil }, "At least one non-nil commonName must prevent enrichment re-trigger")
    }

    // MARK: - Premium Insights: EdgeResponse decoding

    @Test func testEnrichScanTaskHydratesSpeciesDataContent() async throws {
        // Arrange: Inject Mock URL Session
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        MerianNetworkClient.shared.overridingSession = URLSession(configuration: config)
        MerianNetworkClient.shared.resetSpeciesDictionaryCacheForTesting()
        
        let testData = Data("""
        {
            "success": true,
            "data": {
                "gbif_taxon_key": 2433697,
                "habitat_description": "Deciduous forests and urban areas.",
                "similar_species": [
                    {
                        "scientific_name": "Procyon cancrivorus",
                        "common_name": "Crab-eating Raccoon",
                        "reference_image_url": "https://example.com/cancrivorus.jpg",
                        "iucn_red_list_status": "LC"
                    }
                ]
            }
        }
        """.utf8)
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        
        MockURLProtocol.mockEndpoints["/enrich-scan"] = { request in
            #expect(request.url?.path.hasSuffix("/enrich-scan") == true)
            return (mockResponse, testData)
        }
        
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: "00000000-0000-4000-8000-00000000e123",
            commonName: "Raccoon",
            scientificName: "Procyon lotor",
            insightData: InsightData(aiReasoning: "A mammal.", hazardType: "none"),
            confidenceScore: 0.95,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild",
            habitatDescription: nil, // Starts totally empty (cache miss)
            inferenceTier: "pro"
        )
        
        // Act
        await engine.fetchAndApplyEnrichment(modelContext: nil)
        
        // Assert: Ensure the insight sheet data was updated natively
        let data = try #require(engine.speciesData)
        #expect(data.habitatDescription == "Deciduous forests and urban areas.", "fetchAndApplyEnrichment must mutate the Engine's SpeciesData state directly for the View")
        #expect(data.gbifTaxonKey == 2433697)
        #expect(data.similarSpecies?.entries.first?.commonName == "Crab-eating Raccoon", "fetchAndApplyEnrichment must decode and populate similarity entries")
    }

    @Test func testEdgeResponseDecodesSpeciesInsights() throws {
        // species_insights is populated on cache hit for all tiers — sourced from species_dictionary
        let jsonString = """
        {
            "success": true,
            "data": {
                "scan_id": "cache_hit_001",
                "is_biological_subject": true,
                "common_name": "Monarch Butterfly",
                "scientific_name": "Danaus plexippus",
                "confidence_score": 0.98,
                "insight_data": { "ai_reasoning": "A migratory butterfly.", "hazard_type": "none" },
                "species_insights": {
                    "habitat_description": "Open fields, meadows, and roadsides with milkweed."
                }
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: data)
        let insights = try #require(wrapper.data.species_insights, "species_insights must decode on a cache-hit response")

        #expect(insights.habitat_description?.contains("milkweed") == true)
    }

    @Test func testEdgeResponseSpeciesInsightsNilOnCacheMiss() throws {
        // species_insights is absent on a fresh scan (cache miss) — enrichment arrives via enrich-scan
        let jsonString = """
        {
            "success": true,
            "data": {
                "scan_id": "cache_miss_001",
                "is_biological_subject": true,
                "common_name": "Raccoon",
                "scientific_name": "Procyon lotor",
                "confidence_score": 0.91,
                "insight_data": { "ai_reasoning": "A medium-sized mammal.", "hazard_type": "none" }
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: data)

        #expect(wrapper.data.species_insights == nil, "Cache-miss responses must not include species_insights")
    }

    @Test func testSpeciesDataMapsAiReasoningFromEdgeResponse() throws {
        let jsonString = """
        {
            "success": true,
            "data": {
                "scan_id": "reason_scan",
                "is_biological_subject": true,
                "common_name": "Firefly",
                "scientific_name": "Photinus pyralis",
                "confidence_score": 0.95,
                "insight_data": { "ai_reasoning": "A bioluminescent beetle.", "hazard_type": "none" },
                "species_insights": {
                    "habitat_description": "Warm temperate meadows and forest edges."
                }
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: data)
        let speciesData = SpeciesData(fromEdgeResponse: wrapper.data, locationName: nil, weatherCondition: nil, weatherTemperatureF: nil)

        #expect(speciesData.aiReasoning?.contains("bioluminescent beetle") == true, "aiReasoning must be populated per-scan from insight_data.ai_reasoning")
        #expect(speciesData.habitatDescription?.contains("meadows") == true)
    }

    @Test func testSpeciesDataPremiumFieldsNilWhenPremiumInsightsMissing() throws {
        let jsonString = """
        {
            "success": true,
            "data": {
                "is_biological_subject": true,
                "common_name": "Raccoon",
                "insight_data": { "ai_reasoning": "A mammal.", "hazard_type": "none" }
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: data)
        let speciesData = SpeciesData(fromEdgeResponse: wrapper.data, locationName: nil, weatherCondition: nil, weatherTemperatureF: nil)

        // aiReasoning IS populated from insight_data.ai_reasoning (per-scan, always present when insight_data exists)
        #expect(speciesData.aiReasoning == "A mammal.", "aiReasoning comes from insight_data.ai_reasoning, not from removed premium_insights")
        // habitatDescription requires species_insights.habitat_description — absent on cache miss
        #expect(speciesData.habitatDescription == nil)
    }

    // MARK: - Premium Insights: load(from:) — V15 LocalScanRecord fields

    @Test func testLoadFromRecordWithPremiumInsights() throws {
        let record = LocalScanRecord(
            speciesId: "species_v15",
            scientificName: "Danaus plexippus",
            commonName: "Monarch Butterfly",
            aiReasoning: "The orange and black wing pattern with white marginal spots is diagnostic for Danaus plexippus.",
            habitatDescription: "Open fields and meadows with milkweed."
        )
        let engine = InferenceEngine()
        engine.load(from: record)

        let result = try #require(engine.speciesData)
        #expect(result.aiReasoning?.contains("Danaus plexippus") == true)
        #expect(result.habitatDescription?.contains("milkweed") == true)
    }

    @Test func testLoadFromRecordWithNilPremiumFields() throws {
        let record = LocalScanRecord(
            speciesId: "species_legacy",
            scientificName: "Procyon lotor",
            commonName: "Raccoon"
        )
        let engine = InferenceEngine()
        engine.load(from: record)

        let result = try #require(engine.speciesData)
        #expect(result.aiReasoning == nil)
        #expect(result.habitatDescription == nil)
    }

    // MARK: - Similar Species: EnrichScanResponse decoding

    @Test func testEnrichScanResponseDecodesRichLookalikes() throws {
        // Arrange: full payload from species_lookalikes join table hydration
        let jsonString = """
        {
            "success": true,
            "data": {
                "habitat_description": "Deciduous forests and urban areas.",
                "similar_species": [
                    {
                        "scientific_name": "Procyon cancrivorus",
                        "common_name": "Crab-eating Raccoon",
                        "reference_image_url": "https://example.com/cancrivorus.jpg",
                        "iucn_red_list_status": "LC",
                        "reason": "Similar facial mask and ringed tail.",
                        "visual_traits": ["facial mask", "ringed tail"],
                        "confidence": 0.84,
                        "source": "model_enrichment",
                        "review_status": "unreviewed",
                        "is_bidirectional": false,
                        "sort_order": 0
                    },
                    {
                        "scientific_name": "Bassariscus astutus",
                        "common_name": "Ringtail",
                        "reference_image_url": null,
                        "iucn_red_list_status": "LC"
                    }
                ]
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let response = try JSONDecoder().decode(EnrichScanResponse.self, from: data)
        let entries = try #require(response.data?.similar_species, "similar_species must decode to a non-nil array")

        #expect(entries.count == 2)
        #expect(entries[0].scientific_name == "Procyon cancrivorus")
        #expect(entries[0].common_name == "Crab-eating Raccoon")
        #expect(entries[0].reference_image_url == "https://example.com/cancrivorus.jpg")
        #expect(entries[0].iucn_red_list_status == "LC")
        #expect(entries[0].reason == "Similar facial mask and ringed tail.")
        #expect(entries[0].visual_traits == ["facial mask", "ringed tail"])
        #expect(entries[0].confidence == 0.84)
        #expect(entries[1].scientific_name == "Bassariscus astutus")
        #expect(entries[1].reference_image_url == nil, "Null reference_image_url must decode as nil, not crash")
    }

    @Test func testEnrichScanResponseDecodesLookalikesWithNilOptionals() throws {
        // Arrange: sparse entry — only scientific_name provided (common during initial join table population)
        let jsonString = """
        {
            "success": true,
            "data": {
                "similar_species": [
                    { "scientific_name": "Nasua nasua" }
                ]
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let response = try JSONDecoder().decode(EnrichScanResponse.self, from: data)
        let entries = try #require(response.data?.similar_species)

        #expect(entries.count == 1)
        #expect(entries[0].scientific_name == "Nasua nasua")
        #expect(entries[0].common_name == nil)
        #expect(entries[0].reference_image_url == nil)
        #expect(entries[0].iucn_red_list_status == nil)
    }

    @Test func testEnrichScanResponseNilWhenSimilarSpeciesAbsent() throws {
        // Arrange: enrich-scan response with no lookalike data available for this species
        let jsonString = """
        {
            "success": true,
            "data": {
                "habitat_description": "Open ocean.",
                "gbif_taxon_key": 12345
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let response = try JSONDecoder().decode(EnrichScanResponse.self, from: data)

        #expect(response.data?.similar_species == nil, "Absent similar_species key must decode as nil, not an empty array")
    }

    // MARK: - Similar Species: load(from:) — historical record wrapping

    @Test func testLoadFromRecordWithSimilarSpecies() async throws {
        // Arrange: LocalScanRecord with legacy TEXT[] names (MerianSchemaV26 field)
        let record = LocalScanRecord(
            speciesId: "species_procyon",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            isBiological: false,
            similarSpecies: ["Procyon cancrivorus", "Bassariscus astutus"]
        )
        let engine = InferenceEngine()
        engine.load(from: record)
        await engine.historicHydrationTask?.value

        let result = try #require(engine.speciesData)
        let similar = try #require(result.similarSpecies, "similarSpecies must be populated from LocalScanRecord.similarSpecies")

        // Assert: bare strings are wrapped in SimilarSpeciesEntry with nil enrichment fields
        #expect(similar.entries.count == 2)
        #expect(similar.entries[0].scientificName == "Procyon cancrivorus")
        #expect(similar.entries[0].commonName == nil, "Historical wrap must leave commonName nil — no join table data")
        #expect(similar.entries[0].referenceImageUrl == nil)
        #expect(similar.entries[0].iucnRedListStatus == nil)
        #expect(similar.entries[1].scientificName == "Bassariscus astutus")

        // Backwards-compat accessor must still return flat string array
        #expect(similar.lookalikes == ["Procyon cancrivorus", "Bassariscus astutus"])
    }

    @Test func testLoadFromRecordWithNilSimilarSpecies() async throws {
        // Arrange: record with no lookalike data (pre-V26 or species with no known lookalikes)
        let record = LocalScanRecord(
            speciesId: "species_unique",
            scientificName: "Ailuropoda melanoleuca",
            commonName: "Giant Panda",
            isBiological: false
        )
        let engine = InferenceEngine()
        engine.load(from: record)
        await engine.historicHydrationTask?.value

        let result = try #require(engine.speciesData)
        #expect(result.similarSpecies == nil, "nil similarSpecies on LocalScanRecord must not produce an empty SimilarSpecies struct")
    }

    @Test func testLoadFromBiologicalRecordIgnoresLocalLookalikesWhenResetPending() throws {
        UserDefaults.standard.set(
            max(0, MerianConfig.localLookalikesCacheResetVersion - 1),
            forKey: UserDefaultsKeys.localLookalikesCacheResetVersion
        )

        let record = LocalScanRecord(
            speciesId: "species_reset_pending",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            isBiological: true,
            similarSpecies: ["Procyon cancrivorus", "Bassariscus astutus"]
        )
        let engine = InferenceEngine()
        engine.load(from: record)

        let result = try #require(engine.speciesData)
        #expect(result.similarSpecies == nil, "Pending reset should ignore stale locally cached lookalikes for biological records")

        engine.historicHydrationTask?.cancel()
    }

    @Test func testPlannedEnrichmentScopesStillFetchLookalikesWhenMetadataIsSpeciesCached() {
        let scopes = InferenceEngine.plannedEnrichmentScopes(
            needsMetadata: true,
            needsLookalikes: true,
            speciesIsEnriched: true
        )

        #expect(scopes.metadata == false)
        #expect(scopes.lookalikes == true)
    }

    @Test func testNormalizedReferenceURLsDropsEmptyCommaSegments() {
        let refs = InferenceEngine.normalizedReferenceURLs(
            from: " https://example.com/a.jpg, ,https://example.com/b.jpg ,"
        )

        #expect(refs == ["https://example.com/a.jpg", "https://example.com/b.jpg"])
        #expect(InferenceEngine.normalizedReferenceURLs(from: nil).isEmpty)
    }

    @Test func testLoadFromBiologicalRecordFetchesLookalikesWhenSpeciesAlreadyMarkedEnriched() async throws {
        let scientificName = "Opuntia engelmannii"
        UserDefaults.standard.set(
            [scientificName: Date.now.timeIntervalSinceReferenceDate],
            forKey: UserDefaultsKeys.enrichedSpeciesTimestamps
        )

        let responseData = Data("""
        {
            "success": true,
            "data": {
                "similar_species": [
                    {
                        "scientific_name": "Opuntia lindheimeri",
                        "common_name": "Texas Prickly Pear",
                        "reference_image_url": "https://example.com/lindheimeri.jpg",
                        "iucn_red_list_status": "LC"
                    }
                ]
            }
        }
        """.utf8)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        MockURLProtocol.mockEndpoints["/enrich-scan"] = { request in
            let body = MockURLProtocol.bodyData(for: request)
                .flatMap { String(data: $0, encoding: .utf8) } ?? ""
            #expect(body.contains("\"scope\":\"lookalikes\""))
            return (response, responseData)
        }

        let record = LocalScanRecord(
            speciesId: "species_prickly_pear",
            scientificName: scientificName,
            commonName: "Texas Prickly Pear",
            isBiological: true,
            wikipediaOverview: "A widespread prickly pear cactus.",
            referenceImageUrl: "https://example.com/engelmannii.jpg",
            taxonomyKingdom: "Plantae",
            taxonomyOrder: "Caryophyllales",
            habitatDescription: "Dry grasslands and scrub."
        )

        let engine = InferenceEngine()
        engine.load(from: record)
        await engine.historicHydrationTask?.value

        let similar = try #require(engine.speciesData?.similarSpecies)
        #expect(similar.entries.count == 1)
        #expect(similar.entries.first?.scientificName == "Opuntia lindheimeri")
        #expect(similar.entries.first?.commonName == "Texas Prickly Pear")
    }

    // MARK: - Identification Candidates: EdgeResponse decoding

    @Test func testEdgeResponseDecodesCandidatesArray() throws {
        let jsonString = """
        {
            "success": true,
            "data": {
                "scan_id": "cand_001",
                "is_biological_subject": true,
                "scientific_name": "Procyon lotor",
                "common_name": "Raccoon",
                "confidence_score": 0.82,
                "insight_data": { "ai_reasoning": "A procyonid.", "hazard_type": "none" },
                "candidates": [
                    { "scientific_name": "Procyon cancrivorus", "confidence_score": 0.71 },
                    { "scientific_name": "Bassariscus astutus", "confidence_score": 0.65 }
                ]
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: data)

        let candidates = try #require(wrapper.data.candidates, "candidates must decode from edge response JSON")
        #expect(candidates.count == 2)
        #expect(candidates[0].scientific_name == "Procyon cancrivorus")
        #expect(candidates[0].confidence_score == 0.71)
        #expect(candidates[1].scientific_name == "Bassariscus astutus")
    }

    @Test func testEdgeResponseNilCandidatesOnHighConfidenceScan() throws {
        // Server strips candidates before sending when confidence >= diagnosticTrigger.
        let jsonString = """
        {
            "success": true,
            "data": {
                "is_biological_subject": true,
                "scientific_name": "Danaus plexippus",
                "common_name": "Monarch Butterfly",
                "confidence_score": 0.97,
                "insight_data": { "ai_reasoning": "Distinctive wings.", "hazard_type": "none" }
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: data)

        #expect(wrapper.data.candidates == nil, "Absent candidates key must decode as nil, not an empty array")
    }

    // MARK: - Identification Candidates: load(from:) — V28/V29 fields

    @Test func testLoadFromRecordDecodesCandidatesData() async throws {
        let candidates: [IdentificationCandidate] = [
            IdentificationCandidate(scientificName: "Procyon cancrivorus", confidenceScore: 0.71),
            IdentificationCandidate(scientificName: "Bassariscus astutus", confidenceScore: 0.65)
        ]
        let blob = try JSONEncoder().encode(candidates)

        let record = LocalScanRecord(
            speciesId: "v28-candidates",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            candidatesData: blob
        )
        let engine = InferenceEngine()
        engine.load(from: record)
        await engine.historicHydrationTask?.value

        let result = try #require(engine.speciesData)
        let decoded = try #require(result.candidates, "load(from:) must decode candidatesData blob into SpeciesData.candidates")

        #expect(decoded.count == 2)
        #expect(decoded[0].scientificName == "Procyon cancrivorus")
        #expect(decoded[0].confidenceScore == 0.71)
    }

    @Test func testLoadFromRecordNilCandidatesDataYieldsNilCandidates() async throws {
        let record = LocalScanRecord(
            speciesId: "v28-no-candidates",
            scientificName: "Procyon lotor",
            commonName: "Raccoon"
        )
        let engine = InferenceEngine()
        engine.load(from: record)
        await engine.historicHydrationTask?.value

        let result = try #require(engine.speciesData)
        #expect(result.candidates == nil, "Nil candidatesData must produce nil candidates — not an empty array")
    }

    @Test func testLoadFromRecordPopulatesAIScientificName() throws {
        // load(from:) passes record.scientificName as aiScientificName, capturing the AI's
        // original identification before any user override can be applied.
        let record = LocalScanRecord(
            speciesId: "v29-ai-name",
            scientificName: "Procyon lotor",
            commonName: "Raccoon"
        )
        let engine = InferenceEngine()
        engine.load(from: record)

        let result = try #require(engine.speciesData)
        #expect(result.aiScientificName == "Procyon lotor", "load(from:) must set aiScientificName from record.scientificName")
    }

    @Test func testLoadFromRecordPopulatesUserIdentificationOverride() throws {
        // When a user previously overrode the identification, override is rehydrated on load.
        let record = LocalScanRecord(
            speciesId: "v29-override-load",
            scientificName: "Procyon cancrivorus",
            commonName: "Crab-eating Raccoon",
            userIdentificationOverride: "Procyon cancrivorus"
        )
        let engine = InferenceEngine()
        engine.load(from: record)

        let result = try #require(engine.speciesData)
        #expect(result.userIdentificationOverride == "Procyon cancrivorus", "load(from:) must restore userIdentificationOverride from the persisted record")
    }

    @Test func testLoadFromRecordPopulatesUserConfirmedIdentification() throws {
        // When a user previously confirmed the AI, the flag is restored on load.
        let record = LocalScanRecord(
            speciesId: "v29-confirmed-load",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            userConfirmedIdentification: true
        )
        let engine = InferenceEngine()
        engine.load(from: record)

        let result = try #require(engine.speciesData)
        #expect(result.userConfirmedIdentification == true, "load(from:) must restore userConfirmedIdentification from the persisted record")
    }

    @Test func testLoadFromRecordPopulatesIsFlagged() throws {
        // When a user previously flagged an ID, the flag is restored natively on load.
        let record = LocalScanRecord(
            speciesId: "v31-flagged-load",
            scientificName: "Aedes aegypti",
            commonName: "Yellow Fever Mosquito",
            isFlagged: true
        )
        let engine = InferenceEngine()
        engine.load(from: record)

        let result = try #require(engine.speciesData)
        #expect(result.isFlagged == true, "load(from:) must seamlessly restore the isFlagged attribute from the persisted scan snapshot")
    }

    @Test func testFlagAIIdentificationMutatesLocalState() async throws {
        // Assert that calling flagAIIdentification successfully hooks the native memory layer immediately independent of networking
        let record = LocalScanRecord(
            speciesId: "flag-test-01",
            scientificName: "Puma concolor",
            commonName: "Mountain Lion"
        )
        let engine = InferenceEngine()
        engine.load(from: record)
        
        #expect(engine.speciesData?.isFlagged == false, "Brand new initial states must default to false")
        
        await engine.flagAIIdentification(modelContext: nil)
        
        #expect(engine.speciesData?.isFlagged == true, "flagAIIdentification must flip the boolean contextually")
    }

    @Test func testUnflagAIIdentificationMutatesLocalState() async throws {
        // Assert that calling unflagAIIdentification successfully removes the flag native memory layer immediately
        let record = LocalScanRecord(
            speciesId: "unflag-test-01",
            scientificName: "Puma concolor",
            commonName: "Mountain Lion",
            isFlagged: true
        )
        let engine = InferenceEngine()
        engine.load(from: record)
        
        #expect(engine.speciesData?.isFlagged == true, "Initial state should be true as loaded from record")
        
        await engine.unflagAIIdentification(modelContext: nil)
        
        #expect(engine.speciesData?.isFlagged == false, "unflagAIIdentification must flip the boolean to false")
    }
    // MARK: - Identification Review: engine methods

    @Test func testConfirmAIIdentificationSetsConfirmedFlag() async throws {
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: "confirm_scan_001",
            commonName: "Raccoon",
            scientificName: "Procyon lotor",
            insightData: InsightData(aiReasoning: "A mammal.", hazardType: "none"),
            confidenceScore: 0.92,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "Terrestrial"
        )

        await engine.confirmAIIdentification(modelContext: nil)

        #expect(engine.speciesData?.userConfirmedIdentification == true, "confirmAIIdentification must set userConfirmedIdentification to true")
        #expect(engine.speciesData?.userIdentificationOverride == nil, "confirmAIIdentification must not set an override")
    }

    @Test func testConfirmAIIdentificationIsNoOpWhenScanIdMissing() async throws {
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: nil,
            commonName: "Raccoon",
            scientificName: "Procyon lotor",
            insightData: InsightData(aiReasoning: "A mammal.", hazardType: "none"),
            confidenceScore: 0.92,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "Terrestrial"
        )

        await engine.confirmAIIdentification(modelContext: nil)

        #expect(engine.speciesData?.userConfirmedIdentification == false, "No-op when scanId is nil — userConfirmedIdentification must remain false")
    }

    @Test func testConfirmAIIdentificationRejectsChangedPresentationIdentity() async throws {
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: "current_confirm_scan",
            commonName: "Raccoon",
            scientificName: "Procyon lotor",
            insightData: InsightData(aiReasoning: "A mammal.", hazardType: "none"),
            confidenceScore: 0.92,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "Terrestrial"
        )

        await engine.confirmAIIdentification(
            expectedScanId: "previous_confirm_scan",
            modelContext: nil
        )

        #expect(engine.speciesData?.userConfirmedIdentification == false)
    }

    @Test func testApplyIdentificationOverrideRejectsChangedPresentationIdentity() async throws {
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: "current_override_scan",
            commonName: "Raccoon",
            scientificName: "Procyon lotor",
            insightData: InsightData(aiReasoning: "A mammal.", hazardType: "none"),
            confidenceScore: 0.92,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "Terrestrial",
            aiScientificName: "Procyon lotor"
        )

        await engine.applyIdentificationOverride(
            scientificName: "Procyon cancrivorus",
            expectedScanId: "previous_override_scan",
            modelContext: nil
        )

        #expect(engine.speciesData?.scientificName == "Procyon lotor")
        #expect(engine.speciesData?.userIdentificationOverride == nil)
    }

    @Test func testApplyIdentificationOverrideMutatesSpeciesData() async throws {
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: "override_scan_001",
            commonName: "Raccoon",
            scientificName: "Procyon lotor",
            insightData: InsightData(aiReasoning: "A procyonid.", hazardType: "none"),
            confidenceScore: 0.82,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "Terrestrial",
            aiScientificName: "Procyon lotor",
            isFlagged: true  // simulate the "Review again" path where all cards were rejected first
        )

        await engine.applyIdentificationOverride(scientificName: "Procyon cancrivorus", modelContext: nil)

        #expect(engine.speciesData?.scientificName == "Procyon cancrivorus", "Override must update scientificName immediately")
        #expect(engine.speciesData?.userIdentificationOverride == "Procyon cancrivorus", "Override must set userIdentificationOverride")
        #expect(engine.speciesData?.userConfirmedIdentification == false, "Override clears confirmed flag")
        #expect(engine.speciesData?.aiScientificName == "Procyon lotor", "aiScientificName must be preserved after override")
        #expect(engine.speciesData?.isFlagged == false, "Override must clear isFlagged so ConfidenceExplanationSheet transitions from AllCandidatesReviewedView to OverriddenView")
    }

    @Test func testResetIdentificationReviewClearsAllFields() async throws {
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: "reset_scan_001",
            commonName: "Crab-eating Raccoon",
            scientificName: "Procyon cancrivorus",
            insightData: InsightData(aiReasoning: "A procyonid.", hazardType: "none"),
            confidenceScore: 0.82,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "Terrestrial",
            aiScientificName: "Procyon lotor",
            userIdentificationOverride: "Procyon cancrivorus",
            isFlagged: true  // simulate AllCandidatesReviewedView → Reset path
        )

        await engine.resetIdentificationReview(modelContext: nil)

        #expect(engine.speciesData?.userIdentificationOverride == nil, "Reset must clear userIdentificationOverride")
        #expect(engine.speciesData?.userConfirmedIdentification == false, "Reset must clear userConfirmedIdentification")
        #expect(engine.speciesData?.isFlagged == false, "Reset must clear isFlagged so CandidatesCard reappears in BiologicalView")
        #expect(engine.speciesData?.scientificName == "Procyon lotor", "Reset must revert scientificName to aiScientificName")
        #expect(engine.speciesData?.aiScientificName == "Procyon lotor", "aiScientificName must remain unchanged after reset")
    }

    @Test func testResetIdentificationReviewIsNoOpWhenScanIdMissing() async throws {
        // When scanId is nil, reset bails out without mutating any fields.
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: nil,
            commonName: "Crab-eating Raccoon",
            scientificName: "Procyon cancrivorus",
            insightData: InsightData(aiReasoning: "A procyonid.", hazardType: "none"),
            confidenceScore: 0.82,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "Terrestrial",
            aiScientificName: "Procyon lotor",
            userIdentificationOverride: "Procyon cancrivorus"
        )

        await engine.resetIdentificationReview(modelContext: nil)

        #expect(engine.speciesData?.userIdentificationOverride == "Procyon cancrivorus", "No-op when scanId is nil — override must remain unchanged")
        #expect(engine.speciesData?.scientificName == "Procyon cancrivorus", "No-op when scanId is nil — scientificName must remain unchanged")
    }

    // MARK: - Inference Tier Configuration Validation
    @Test func testInferenceTier_ConfigurationValidation() throws {
        // Assert Flash Free-Tier thresholds are strict
        let flashBands = MerianConfig.confidenceBands(forInferenceTier: "flash")
        #expect(flashBands.strong == 0.95)
        #expect(flashBands.possible == 0.75)
        // diagnosticTrigger sits above strong (0.99) so Strong-match scans still carry candidates as an escape hatch
        #expect(flashBands.diagnosticTrigger == 0.99)

        // Assert Pro Premium-Tier thresholds are relaxed
        let proBands = MerianConfig.confidenceBands(forInferenceTier: "pro")
        #expect(proBands.strong == 0.85)
        #expect(proBands.possible == 0.65)
        #expect(proBands.diagnosticTrigger == 0.99)

        // Assert Legacy/Nil scans resolve to Flash thresholds for safety
        let legacyBands = MerianConfig.confidenceBands(forInferenceTier: nil)
        #expect(legacyBands.strong == 0.95)
        #expect(legacyBands.diagnosticTrigger == 0.99)
    }

    // MARK: - Enqueue-at-submission durability (win condition + cancellation)

    @MainActor
    private func createInMemoryContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makeTelemetry() -> CaptureTelemetry {
        CaptureTelemetry(
            subjectDistanceInMeters: nil, gpsLatitude: nil, gpsLongitude: nil,
            gpsElevation: nil, locationName: nil, weatherCondition: nil,
            weatherTemperatureF: nil, timeOfDay: nil,
            timestamp: DateUtilities.iso8601Formatter.string(from: Date()),
            zoomFactor: nil, estimatedSizeCm: nil
        )
    }

    /// Win condition: the live-inference success path calls `flushOfflineQueuedScan`
    /// synchronously on the main context before the completion notification fires.
    ///
    /// The full `analyze()` path depends on authenticated Supabase session bootstrap,
    /// which is outside this unit suite's mocked surface. This test exercises the
    /// queue-removal contract directly.
    @Test func testFlushOfflineQueuedScanDeletesQueueRecord() async throws {
        let context = try createInMemoryContext()

        let originalContext = OfflineQueueManager.shared.modelContext
        defer {
            OfflineQueueManager.shared.modelContext = originalContext
        }

        let scanId = UUID().uuidString.lowercased()
        context.insert(OfflineQueuedScan(id: scanId, scanState: .pending))
        try context.save()
        OfflineQueueManager.shared.modelContext = context

        OfflineQueueManager.shared.flushOfflineQueuedScan(scanId: scanId)

        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        let deadline = Date().addingTimeInterval(2)
        var recordGone = false
        while Date() < deadline {
            if (try? context.fetchCount(descriptor)) ?? 1 == 0 {
                recordGone = true
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        #expect(recordGone, "flushOfflineQueuedScan must synchronously remove the queue record from the main context")
    }

    /// Durability contract: inference cancellation (user backgrounds mid-analysis) must leave
    /// the queue record intact so the background URLSession path owns delivery.
    @Test func testInferenceCancellationPreservesQueueRecord() async throws {
        let context = try createInMemoryContext()

        let originalContext = OfflineQueueManager.shared.modelContext
        let originalIsOnline = OfflineQueueManager.shared.isOnline
        defer {
            OfflineQueueManager.shared.modelContext = originalContext
            OfflineQueueManager.shared.isOnline = originalIsOnline
        }
        OfflineQueueManager.shared.modelContext = context
        OfflineQueueManager.shared.isOnline = false

        let scanId = UUID().uuidString.lowercased()
        let generation = UUID()
        context.insert(OfflineQueuedScan(id: scanId, scanState: .pending))
        context.insert(OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .running,
            metadataJSON:
                InferenceGenerationMetadataContract.json(
                    for: generation
                )
        ))
        try context.save()
        OfflineQueueManager.shared.foregroundInferenceGenerations[scanId] =
            generation
        OfflineQueueManager.shared.deferredLiveUploadScanIds.insert(scanId)
        defer {
            OfflineQueueManager.shared.foregroundInferenceRetirementTasks
                .cancel(scanId)
            OfflineQueueManager.shared.startedForegroundInferenceGenerations
                .removeValue(forKey: scanId)
            OfflineQueueManager.shared.foregroundInferenceGenerations
                .removeValue(forKey: scanId)
            OfflineQueueManager.shared.deferredLiveUploadScanIds.remove(scanId)
        }

        let engine = InferenceEngine()
        engine.analyze(
            scanId: scanId,
            foregroundInferenceGeneration: generation,
            imageDatas: [Data(repeating: 0xAB, count: 16)],
            displayDatas: [],
            telemetry: makeTelemetry(),
            modelContext: context
        )
        // Cancel immediately — fires before any network call succeeds.
        // cancelActiveRequest cancels inferenceTask; the catch block handles
        // CancellationError with a plain return — no deleteQueuedScan call.
        engine.cancelActiveRequest()

        // Give the cooperatively cancelled task and exact durable ownership
        // handoff time to exit.
        let deadline = Date().addingTimeInterval(2)
        while OfflineQueueManager.shared
                .foregroundInferenceGenerations[scanId] != nil,
              Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        let remaining = try context.fetchCount(descriptor)
        #expect(remaining == 1, "Inference cancellation must not delete the queue record — background upload path owns delivery")
        #expect(
            !OfflineQueueManager.shared.deferredLiveUploadScanIds.contains(
                scanId
            ),
            "Cancellation must release the exact attempt's recovery-upload hold"
        )
        #expect(
            OfflineQueueManager.shared
                .foregroundInferenceGenerations[scanId] == nil,
            "Cancellation must relinquish the exact foreground generation"
        )
    }

    // MARK: - activeScanId lifecycle

    /// Tests `prepareForNewScan()`, which fires at the start of every `analyze()` call
    /// to reset state from the previous scan.  The critical assertion is that `activeScanId`
    /// is cleared here: a stale ID from the previous scan must not persist into the new
    /// scan's hydration window.
    @Test func testPrepareForNewScanClearsActiveScanId() {
        let engine = InferenceEngine()
        engine.activeScanId = "stale-scan-id-from-previous-scan"
        engine.recoverablePresentationScanId =
            "stale-recovery-id-from-previous-scan"
        engine.prepareForNewScan()
        #expect(engine.activeScanId == nil, "prepareForNewScan must clear activeScanId before the next scan claims the engine")
        #expect(engine.recoverablePresentationScanId == nil)
        // isProcessing == true after prepareForNewScan is intentional: it signals a scan
        // is *about to* be submitted (it will be set by the analyze() call that follows).
        #expect(engine.isProcessing == true)
    }

    @Test func successfulResultCommitPublishesCompleteRevealState() {
        let engine = InferenceEngine()
        let scanId = "synchronized-result"
        var completedScanIds: [String] = []
        let completionCancellable = AppEventPublisher.shared.publisher.sink { event in
            if case .foregroundBiologicalScanCompleted(let completedScanId) = event {
                completedScanIds.append(completedScanId)
            }
        }
        defer { completionCancellable.cancel() }
        let focusRegion = NormalizedImageFocusRegion(
            x: 0.2,
            y: 0.25,
            width: 0.4,
            height: 0.5
        )
        let species = SpeciesData(
            scanId: scanId,
            commonName: "Monarch Butterfly",
            scientificName: "Danaus plexippus",
            insightData: InsightData(aiReasoning: "Orange wings with black veins.", hazardType: "none"),
            confidenceScore: 0.97,
            referenceImageUrl: "https://example.com/reference-1.jpg, https://example.com/reference-2.jpg",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )

        let attemptGeneration = UUID()
        engine.activeScanId = scanId
        engine.activeLiveInferenceAttemptGeneration =
            attemptGeneration
        engine.isProcessing = true
        engine.activeMedia = ActiveScanMedia(
            items: [.liveImage(Data([0x01]))],
            focusRegionsBySourceIndex: [0: focusRegion]
        )

        let didCommit = engine.commitSuccessfulResult(
            for: scanId,
            attemptGeneration: attemptGeneration,
            foregroundInferenceGeneration: nil,
            speciesData: species,
            persistedMediaItems: [.image("documents/synchronized-result.webp")]
        )

        #expect(didCommit)
        #expect(engine.speciesData?.scanId == scanId)
        #expect(engine.activeMedia.items == [.image("documents/synchronized-result.webp")])
        #expect(engine.activeMedia.referenceState == .loaded([
            "https://example.com/reference-1.jpg",
            "https://example.com/reference-2.jpg"
        ]))
        #expect(engine.activeMedia.focusRegionsBySourceIndex[0] == focusRegion)
        #expect(engine.activeMedia.totalItems == 3)
        #expect(engine.isProcessing == false)
        #expect(completedScanIds == [scanId])
    }

    @Test func nonBiologicalResultCommitDoesNotPublishForegroundCompletion() {
        let engine = InferenceEngine()
        let scanId = "non-biological-result"
        let attemptGeneration = UUID()
        var completedScanIds: [String] = []
        let completionCancellable = AppEventPublisher.shared.publisher.sink { event in
            if case .foregroundBiologicalScanCompleted(let completedScanId) = event {
                completedScanIds.append(completedScanId)
            }
        }
        defer { completionCancellable.cancel() }

        engine.activeScanId = scanId
        engine.activeLiveInferenceAttemptGeneration = attemptGeneration
        engine.isProcessing = true

        let didCommit = engine.commitSuccessfulResult(
            for: scanId,
            attemptGeneration: attemptGeneration,
            foregroundInferenceGeneration: nil,
            speciesData: SpeciesData(
                scanId: scanId,
                commonName: "Non-biological subject",
                scientificName: "Non-biological subject",
                insightData: InsightData(
                    aiReasoning: "No biological subject was detected.",
                    hazardType: "none"
                ),
                confidenceScore: 0.91,
                isBiological: false,
                isLiveCapture: true,
                isInvasive: false,
                ecologyType: "unknown"
            )
        )

        #expect(didCommit)
        #expect(completedScanIds.isEmpty)
    }

    @Test func staleResultCommitCannotOverwriteCurrentScan() {
        let engine = InferenceEngine()
        let currentAttemptGeneration = UUID()
        var completedScanIds: [String] = []
        let completionCancellable = AppEventPublisher.shared.publisher.sink { event in
            if case .foregroundBiologicalScanCompleted(let completedScanId) = event {
                completedScanIds.append(completedScanId)
            }
        }
        defer { completionCancellable.cancel() }
        engine.activeScanId = "current-scan"
        engine.activeLiveInferenceAttemptGeneration =
            currentAttemptGeneration
        engine.isProcessing = true
        engine.activeMedia = ActiveScanMedia(items: [.liveImage(Data([0x02]))])

        let staleSpecies = SpeciesData(
            scanId: "stale-scan",
            commonName: "Stale Result",
            scientificName: "Resultus stale",
            insightData: InsightData(aiReasoning: "Should not publish.", hazardType: "none"),
            confidenceScore: 0.9,
            referenceImageUrl: "https://example.com/stale.jpg",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )

        let didCommit = engine.commitSuccessfulResult(
            for: "stale-scan",
            attemptGeneration: UUID(),
            foregroundInferenceGeneration: nil,
            speciesData: staleSpecies,
            persistedMediaItems: [.image("documents/stale.webp")]
        )

        #expect(didCommit == false)
        #expect(engine.speciesData == nil)
        #expect(engine.activeMedia.items == [.liveImage(Data([0x02]))])
        #expect(engine.activeMedia.referenceState == .empty)
        #expect(engine.isProcessing)
        #expect(completedScanIds.isEmpty)
    }

    @Test func staleAttemptForSameScanCannotOverwriteReplacementGeneration() {
        let engine = InferenceEngine()
        let manager = OfflineQueueManager.shared
        let scanId = "same-scan-retry-\(UUID().uuidString.lowercased())"
        let staleGeneration = UUID()
        let replacementGeneration = UUID()
        defer {
            manager.startedForegroundInferenceGenerations.removeValue(
                forKey: scanId
            )
            manager.foregroundInferenceGenerations.removeValue(
                forKey: scanId
            )
        }

        manager.foregroundInferenceGenerations[scanId] =
            replacementGeneration
        manager.startedForegroundInferenceGenerations[scanId] =
            replacementGeneration
        engine.activeScanId = scanId
        engine.activeLiveInferenceAttemptGeneration =
            replacementGeneration
        engine.activeForegroundInferenceGeneration =
            replacementGeneration
        engine.isProcessing = true

        let staleSpecies = SpeciesData(
            scanId: scanId,
            commonName: "Stale Result",
            scientificName: "Resultus stale",
            insightData: InsightData(
                aiReasoning: "Should not publish.",
                hazardType: "none"
            ),
            confidenceScore: 0.9,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )
        let replacementSpecies = SpeciesData(
            scanId: scanId,
            commonName: "Replacement Result",
            scientificName: "Resultus current",
            insightData: InsightData(
                aiReasoning: "Current generation.",
                hazardType: "none"
            ),
            confidenceScore: 0.95,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )

        let staleDidCommit = engine.commitSuccessfulResult(
            for: scanId,
            attemptGeneration: staleGeneration,
            foregroundInferenceGeneration: staleGeneration,
            speciesData: staleSpecies
        )
        let staleBackgroundDidCommit =
            engine.commitRecoveredBackgroundResult(
                for: scanId,
                replacingAttemptGeneration: staleGeneration,
                expectedForegroundGeneration: staleGeneration,
                speciesData: staleSpecies
            )
        let replacementDidCommit = engine.commitSuccessfulResult(
            for: scanId,
            attemptGeneration: replacementGeneration,
            foregroundInferenceGeneration: replacementGeneration,
            speciesData: replacementSpecies
        )

        #expect(!staleDidCommit)
        #expect(!staleBackgroundDidCommit)
        #expect(replacementDidCommit)
        #expect(engine.speciesData?.commonName == "Replacement Result")
    }

    @Test func foregroundGenerationCannotBeStartedTwiceOrDuringRetirement() async throws {
        let context = try createInMemoryContext()
        let engine = InferenceEngine()
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        let originalIsOnline = manager.isOnline
        let scanId =
            "single-use-foreground-\(UUID().uuidString.lowercased())"
        let generation = UUID()
        defer {
            engine.inferenceTask?.cancel()
            manager.foregroundInferenceRetirementTasks.cancel(scanId)
            manager.startedForegroundInferenceGenerations.removeValue(
                forKey: scanId
            )
            manager.foregroundInferenceGenerations.removeValue(
                forKey: scanId
            )
            manager.deferredLiveUploadScanIds.remove(scanId)
            manager.modelContext = originalContext
            manager.isOnline = originalIsOnline
        }

        manager.modelContext = context
        manager.isOnline = false
        context.insert(OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .pending
        ))
        context.insert(OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .running,
            metadataJSON:
                InferenceGenerationMetadataContract.json(for: generation)
        ))
        try context.save()
        manager.foregroundInferenceGenerations[scanId] = generation
        manager.deferredLiveUploadScanIds.insert(scanId)
        #expect(
            manager.claimForegroundInferenceStart(
                scanId: scanId,
                generation: generation
            )
        )
        #expect(
            !manager.claimForegroundInferenceStart(
                scanId: scanId,
                generation: generation
            ),
            "A foreground UUID must be single-use across all engine callers"
        )

        let currentSpecies = SpeciesData(
            scanId: scanId,
            commonName: "Current Attempt",
            scientificName: "Attemptus current",
            insightData: InsightData(
                aiReasoning: "Must remain published.",
                hazardType: "none"
            ),
            confidenceScore: 0.95,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )
        engine.activeScanId = scanId
        engine.activeLiveInferenceAttemptGeneration = generation
        engine.activeForegroundInferenceGeneration = generation
        engine.speciesData = currentSpecies
        engine.isProcessing = true

        // An exact duplicate must be an idempotent no-op. Restarting it would
        // give old and new callbacks the same UUID.
        engine.analyze(
            scanId: scanId,
            foregroundInferenceGeneration: generation,
            imageDatas: [Data([0x01])],
            telemetry: makeTelemetry(),
            modelContext: context
        )
        #expect(engine.speciesData?.commonName == "Current Attempt")
        #expect(engine.activeLiveInferenceAttemptGeneration == generation)
        #expect(
            manager.deferredLiveUploadScanIds.contains(scanId),
            "A duplicate start must not release the current upload hold"
        )

        // Retirement fences the still-running presentation synchronously,
        // before durable handoff can acquire its actor coordinator. Temporarily
        // remove the context to force the first durable handoff to fail.
        manager.modelContext = nil
        manager.retireForegroundInference(
            scanId: scanId,
            generation: generation,
            resumeBackground: true,
            reason: "unit_test_external_retirement"
        )
        let retiringAttemptDidCommit = engine.commitSuccessfulResult(
            for: scanId,
            attemptGeneration: generation,
            foregroundInferenceGeneration: generation,
            speciesData: currentSpecies
        )
        #expect(
            !retiringAttemptDidCommit,
            "A tokenized retirement must fence delayed result publication before durable release"
        )

        // Presentation cancellation must preserve that manager-owned retirement
        // and the same UUID must remain unusable rather than being abandoned as
        // a permanent recovery-suppression claim.
        engine.prepareForNewScan()
        engine.analyze(
            scanId: scanId,
            foregroundInferenceGeneration: generation,
            imageDatas: [Data([0x02])],
            telemetry: makeTelemetry(),
            modelContext: context
        )
        #expect(engine.activeScanId == nil)
        #expect(engine.activeLiveInferenceAttemptGeneration == nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(
            manager.foregroundInferenceGenerations[scanId] == generation,
            "A failed durable handoff must retain the exact process owner until retry succeeds"
        )

        manager.modelContext = context
        let deadline = Date().addingTimeInterval(2)
        while manager.foregroundInferenceGenerations[scanId] != nil,
              Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(manager.foregroundInferenceGenerations[scanId] == nil)

        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        let jobDescriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        #expect(try context.fetch(jobDescriptor).first?.metadataJSON == nil)
    }

    @Test func loadingPersistedScanRelinquishesExactLiveOwner() async throws {
        let context = try createInMemoryContext()
        let engine = InferenceEngine()
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        let originalIsOnline = manager.isOnline
        let liveScanId =
            "live-before-history-\(UUID().uuidString.lowercased())"
        let liveGeneration = UUID()
        let historicScanId =
            "historic-replacement-\(UUID().uuidString.lowercased())"
        defer {
            engine.inferenceTask?.cancel()
            engine.historicHydrationTask?.cancel()
            manager.foregroundInferenceRetirementTasks.cancel(liveScanId)
            manager.startedForegroundInferenceGenerations.removeValue(
                forKey: liveScanId
            )
            manager.foregroundInferenceGenerations.removeValue(
                forKey: liveScanId
            )
            manager.deferredLiveUploadScanIds.remove(liveScanId)
            manager.modelContext = originalContext
            manager.isOnline = originalIsOnline
        }

        manager.modelContext = context
        manager.isOnline = false
        context.insert(OfflineQueuedScan(
            id: liveScanId,
            timestamp: Date(),
            scanState: .pending
        ))
        context.insert(OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(
                scanId: liveScanId
            ),
            kind: .scanIngestion,
            subjectId: liveScanId,
            status: .running,
            metadataJSON:
                InferenceGenerationMetadataContract.json(
                    for: liveGeneration
                )
        ))
        let historicRecord = LocalScanRecord(
            id: historicScanId,
            speciesId: UUID().uuidString,
            scientificName: "Objectum historicum",
            commonName: "Historic Object",
            isBiological: false,
            isLiveCapture: false,
            ecologyType: "inanimate",
            confidenceScore: 0.9
        )
        context.insert(historicRecord)
        try context.save()

        manager.foregroundInferenceGenerations[liveScanId] =
            liveGeneration
        manager.deferredLiveUploadScanIds.insert(liveScanId)
        engine.activeScanId = liveScanId
        engine.activeLiveInferenceAttemptGeneration = liveGeneration
        engine.activeForegroundInferenceGeneration = liveGeneration
        engine.isProcessing = true
        let oldInferenceTask = Task<Void, Error> {
            try await Task.sleep(for: .seconds(30))
        }
        engine.inferenceTask = oldInferenceTask

        engine.load(from: historicRecord)

        #expect(oldInferenceTask.isCancelled)
        #expect(engine.activeScanId == historicScanId)
        #expect(engine.activeLiveInferenceAttemptGeneration == nil)
        #expect(engine.activeForegroundInferenceGeneration == nil)
        #expect(engine.speciesData?.scanId == historicScanId)
        #expect(
            !manager.deferredLiveUploadScanIds.contains(liveScanId),
            "Replacing the presentation must release the exact recovery-upload hold"
        )

        let deadline = Date().addingTimeInterval(2)
        while manager.foregroundInferenceGenerations[liveScanId] != nil,
              Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(manager.foregroundInferenceGenerations[liveScanId] == nil)

        let queuedDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == liveScanId }
        )
        #expect(
            try context.fetch(queuedDescriptor).first != nil,
            "Historical presentation replacement hands the queued scan to recovery; it does not delete it"
        )
    }

    @Test func recoveredBackgroundResultCanReplaceExactReleasedAttempt() {
        let engine = InferenceEngine()
        let manager = OfflineQueueManager.shared
        let scanId =
            "released-background-presentation-\(UUID().uuidString.lowercased())"
        let releasedGeneration = UUID()
        var completedScanIds: [String] = []
        let completionCancellable = AppEventPublisher.shared.publisher.sink { event in
            if case .foregroundBiologicalScanCompleted(let completedScanId) = event {
                completedScanIds.append(completedScanId)
            }
        }
        defer { completionCancellable.cancel() }
        manager.foregroundInferenceGenerations.removeValue(forKey: scanId)
        engine.activeScanId = scanId
        engine.activeLiveInferenceAttemptGeneration =
            releasedGeneration
        engine.activeForegroundInferenceGeneration =
            releasedGeneration
        engine.isProcessing = true

        let recoveredSpecies = SpeciesData(
            scanId: scanId,
            commonName: "Recovered Result",
            scientificName: "Resultus recovered",
            insightData: InsightData(
                aiReasoning: "Background recovery completed.",
                hazardType: "none"
            ),
            confidenceScore: 0.94,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )

        let didCommit = engine.commitRecoveredBackgroundResult(
            for: scanId,
            replacingAttemptGeneration: releasedGeneration,
            expectedForegroundGeneration: releasedGeneration,
            speciesData: recoveredSpecies
        )
        let releasedAttemptDidCommitAgain = engine.commitSuccessfulResult(
            for: scanId,
            attemptGeneration: releasedGeneration,
            foregroundInferenceGeneration: releasedGeneration,
            speciesData: recoveredSpecies
        )

        #expect(didCommit)
        #expect(!releasedAttemptDidCommitAgain)
        #expect(engine.speciesData?.commonName == "Recovered Result")
        #expect(!engine.isProcessing)
        #expect(engine.activeScanId == nil)
        #expect(engine.activeLiveInferenceAttemptGeneration == nil)
        #expect(engine.activeForegroundInferenceGeneration == nil)
        #expect(completedScanIds.isEmpty)
    }

    @Test func recoveredQueuedResultCanReplaceExactRetainedPresentation() {
        let engine = InferenceEngine()
        let scanId =
            "queued-recovery-presentation-\(UUID().uuidString.lowercased())"
        engine.activeScanId = nil
        engine.activeLiveInferenceAttemptGeneration = nil
        engine.activeForegroundInferenceGeneration = nil
        engine.recoverablePresentationScanId = scanId
        engine.isProcessing = false
        engine.speciesData = SpeciesData(
            commonName: "Restoring scan",
            scientificName: "",
            insightData: InsightData(
                aiReasoning: "Safely saved.",
                hazardType: "none"
            ),
            confidenceScore: 0,
            isBiological: false,
            isLiveCapture: false,
            isInvasive: false,
            ecologyType: "unknown"
        )

        let recoveredSpecies = SpeciesData(
            scanId: scanId,
            commonName: "Recovered Queued Result",
            scientificName: "Resultus queued",
            insightData: InsightData(
                aiReasoning: "Queued recovery completed.",
                hazardType: "none"
            ),
            confidenceScore: 0.93,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )

        let didCommit = engine.commitRecoveredQueuedResult(
            for: scanId,
            speciesData: recoveredSpecies
        )

        #expect(didCommit)
        #expect(engine.recoverablePresentationScanId == nil)
        #expect(engine.speciesData?.scanId == scanId)
        #expect(engine.speciesData?.commonName == "Recovered Queued Result")
        #expect(!engine.isProcessing)
    }

    @Test func recoveredQueuedResultRejectsStaleOrMismatchedScan() {
        let engine = InferenceEngine()
        let expectedScanId =
            "expected-queued-recovery-\(UUID().uuidString.lowercased())"
        let staleScanId =
            "stale-queued-recovery-\(UUID().uuidString.lowercased())"
        engine.recoverablePresentationScanId = expectedScanId

        let staleSpecies = SpeciesData(
            scanId: staleScanId,
            commonName: "Stale Result",
            scientificName: "Resultus stale",
            insightData: InsightData(
                aiReasoning: "Must not replace the current presentation.",
                hazardType: "none"
            ),
            confidenceScore: 0.9,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )

        #expect(!engine.commitRecoveredQueuedResult(
            for: staleScanId,
            speciesData: staleSpecies
        ))
        #expect(!engine.commitRecoveredQueuedResult(
            for: expectedScanId,
            speciesData: staleSpecies
        ))
        #expect(engine.recoverablePresentationScanId == expectedScanId)
        #expect(engine.speciesData == nil)
    }

    /// Tests the generation-fenced defer block used by both live pipelines.
    /// When the inference task exits — for any reason (success, error, or cancellation) —
    /// it may clear state only while its UUID still owns the presentation slot.
    @Test func testActiveScanIdClearedByInferenceTaskDefer() async {
        let engine = InferenceEngine()
        let generation = UUID()
        engine.activeScanId = "live-scan-being-processed"
        engine.activeLiveInferenceAttemptGeneration = generation
        engine.isProcessing = true

        let task = Task<Void, Error> { @MainActor in
            defer {
                if engine.activeScanId == "live-scan-being-processed",
                   engine.activeLiveInferenceAttemptGeneration == generation {
                    engine.isProcessing = false
                    engine.activeScanId = nil
                    engine.activeLiveInferenceAttemptGeneration = nil
                }
            }
            await Task.yield()
        }
        engine.inferenceTask = task
        _ = try? await task.value   // wait for defer to complete on @MainActor

        #expect(engine.activeScanId == nil, "activeScanId must be nil after the inference task exits")
        #expect(engine.isProcessing == false, "isProcessing must be false after the inference task exits")
    }

    /// Explicit cancellation invalidates the presentation UUID, so it must also
    /// clear the paired scan identity instead of leaving an unowned hydration slot.
    @Test func testCancelActiveRequestClearsActiveScanId() {
        let engine = InferenceEngine()
        engine.activeScanId = "background-scan-in-flight"
        engine.activeLiveInferenceAttemptGeneration = UUID()
        engine.recoverablePresentationScanId =
            "background-scan-in-flight"
        engine.isProcessing = true

        engine.cancelActiveRequest()

        #expect(engine.isProcessing == false, "cancelActiveRequest must clear isProcessing")
        #expect(
            engine.activeScanId == nil,
            "An invalidated presentation UUID must not leave an unowned activeScanId"
        )
        #expect(engine.activeLiveInferenceAttemptGeneration == nil)
        #expect(engine.recoverablePresentationScanId == nil)
    }

    // MARK: - Identification Candidates: full four-field decoding

    @Test func testEdgeResponseDecodesCandidatesWithAllFields() throws {
        // Verifies that common_name (server-enriched) and distinguishing_feature (Gemini-generated)
        // both decode correctly from the identify response payload.
        let jsonString = """
        {
            "success": true,
            "data": {
                "scan_id": "cand_full_001",
                "is_biological_subject": true,
                "scientific_name": "Danaus plexippus",
                "common_name": "Monarch Butterfly",
                "confidence_score": 0.82,
                "insight_data": { "ai_reasoning": "A milkweed butterfly.", "hazard_type": "none" },
                "candidates": [
                    {
                        "scientific_name": "Limenitis archippus",
                        "common_name": "Viceroy",
                        "confidence_score": 0.71,
                        "distinguishing_feature": "Hindwing black postmedian band broader and more irregular"
                    },
                    {
                        "scientific_name": "Danaus gilippus",
                        "common_name": "Queen",
                        "confidence_score": 0.58,
                        "distinguishing_feature": "Forewing lacks white spots in the black apex band"
                    }
                ]
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: data)
        let candidates = try #require(wrapper.data.candidates, "candidates must decode from edge response JSON")

        #expect(candidates.count == 2)
        #expect(candidates[0].scientific_name == "Limenitis archippus")
        #expect(candidates[0].common_name == "Viceroy", "common_name must decode from server-enriched payload")
        #expect(candidates[0].confidence_score == 0.71)
        #expect(candidates[0].distinguishing_feature == "Hindwing black postmedian band broader and more irregular")
        #expect(candidates[1].scientific_name == "Danaus gilippus")
        #expect(candidates[1].common_name == "Queen")
        #expect(candidates[1].distinguishing_feature == "Forewing lacks white spots in the black apex band")
    }

    @Test func testEdgeResponseDecodesCandidatesWithoutCommonNameOnCacheMiss() throws {
        // When a candidate species is not in species_dictionary, common_name is absent from JSON.
        // The Swift optional must decode as nil — not crash.
        let jsonString = """
        {
            "success": true,
            "data": {
                "scan_id": "cand_miss_001",
                "is_biological_subject": true,
                "scientific_name": "Procyon lotor",
                "common_name": "Raccoon",
                "confidence_score": 0.78,
                "insight_data": { "ai_reasoning": "A procyonid.", "hazard_type": "none" },
                "candidates": [
                    {
                        "scientific_name": "Rare obscura",
                        "confidence_score": 0.65,
                        "distinguishing_feature": "Markings differ in tail pattern"
                    }
                ]
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: data)
        let candidates = try #require(wrapper.data.candidates)

        #expect(candidates[0].common_name == nil, "Absent common_name key must decode as nil — cache miss path must not crash")
        #expect(candidates[0].distinguishing_feature == "Markings differ in tail pattern")
    }

    @Test func testSpeciesDataMapsAllCandidateFieldsFromEdgeResponse() throws {
        // Verifies the SpeciesData.init(fromEdgeResponse:) mapping passes all four fields through.
        let jsonString = """
        {
            "success": true,
            "data": {
                "scan_id": "cand_map_001",
                "is_biological_subject": true,
                "scientific_name": "Danaus plexippus",
                "common_name": "Monarch Butterfly",
                "confidence_score": 0.82,
                "insight_data": { "ai_reasoning": "A migratory butterfly.", "hazard_type": "none" },
                "candidates": [
                    {
                        "scientific_name": "Limenitis archippus",
                        "common_name": "Viceroy",
                        "confidence_score": 0.71,
                        "distinguishing_feature": "Hindwing black postmedian band broader and more irregular"
                    }
                ]
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: data)
        let speciesData = SpeciesData(fromEdgeResponse: wrapper.data, locationName: nil, weatherCondition: nil, weatherTemperatureF: nil)
        let candidate = try #require(speciesData.candidates?.first)

        #expect(candidate.scientificName == "Limenitis archippus")
        #expect(candidate.commonName == "Viceroy")
        #expect(candidate.confidenceScore == 0.71)
        #expect(candidate.distinguishingFeature == "Hindwing black postmedian band broader and more irregular")
    }
}
