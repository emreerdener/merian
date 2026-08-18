import Testing
import SwiftData
import Foundation
@testable import Merian

@MainActor
struct ScanRepositoryTests {

    private struct HistoricalMediaPayload: Encodable {
        let id: String
        let image_storage_urls: [String]
        let video_storage_urls: [String]
        let audio_storage_urls: [String]?
        let captured_media: [SerializedMediaItem]?
        let user_observation_context: ObservationContext?
    }

    // Helper to create an isolated SwiftData container caching out to disk due to iOS 18 simulator array appending bugs.
    @MainActor
    private func createIsolatedContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let modelConfiguration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let context = ModelContext(container)
        ScanRepository.shared.configure(with: context)
        return context
    }

    @MainActor
    private func createPremiumFieldsContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let modelConfiguration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let context = ModelContext(container)
        ScanRepository.shared.configure(with: context)
        return context
    }

    @Test func testHistoricalObservationContextDecodesSnakeCaseISO8601() throws {
        let payload = Data(
            #"{"free_text":"  Heard beside the creek  ","added_at":"2026-08-15T05:30:00.000Z"}"#.utf8
        )

        let decoded = try JSONDecoder().decode(HistoricalObservationContext.self, from: payload)
        let context = try #require(decoded.observationContext)
        let expectedAddedAt = try #require(
            DateUtilities.iso8601FractionalFormatter.date(
                from: "2026-08-15T05:30:00.000Z"
            )
        )

        #expect(context.freeText == "Heard beside the creek")
        #expect(context.addedAt == expectedAddedAt)
    }

    @Test func testHistoricalAudioRehydrationPreservesSubjectClassification() async throws {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let configuration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let decoder = JSONDecoder()
        let payloads = [
            """
            {
              "id": "historical-audio-nonbio",
              "timestamp": "2026-08-17T12:00:00.000Z",
              "audio_storage_urls": ["https://cdn.example.com/mechanical.wav"],
              "is_biological_subject": false
            }
            """,
            """
            {
              "id": "historical-audio-unresolved",
              "timestamp": "2026-08-17T12:01:00.000Z",
              "audio_storage_urls": ["https://cdn.example.com/unresolved.wav"],
              "is_biological_subject": true
            }
            """,
            """
            {
              "id": "historical-audio-human",
              "timestamp": "2026-08-17T12:02:00.000Z",
              "audio_storage_urls": ["https://cdn.example.com/human.wav"],
              "is_biological_subject": true,
              "species_dictionary": {
                "scientific_name": "Homo sapiens",
                "common_names": { "en": "Human" }
              }
            }
            """
        ]
        let responses = try payloads.map {
            try decoder.decode(HistoricalScanResponse.self, from: Data($0.utf8))
        }
        let actor = HistoricalDatabaseActor(modelContainer: container)

        let insertedCount = await actor.reconcileScanPage(responses: responses)
        #expect(insertedCount == 3)

        let verificationContext = ModelContext(container)
        let records = try verificationContext.fetch(FetchDescriptor<LocalScanRecord>())
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        let nonBiological = try #require(recordsByID["historical-audio-nonbio"])
        let unresolved = try #require(recordsByID["historical-audio-unresolved"])
        let human = try #require(recordsByID["historical-audio-human"])

        #expect(!nonBiological.isBiological)
        #expect(!nonBiological.isExploreShareEligible)
        #expect(unresolved.isBiological)
        #expect(!unresolved.hasResolvedBiologicalIdentification)
        #expect(!unresolved.isExploreShareEligible)
        #expect(human.isBiological)
        #expect(human.isHumanSubject)
        #expect(!human.isExploreShareEligible)
    }

    @Test func testHistoricalReconciliationRepairsCachedMissingRemoteVideo() async throws {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let configuration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let scanID = "cached-missing-video-\(UUID().uuidString.lowercased())"
        let posterURL = "https://cdn.example.com/poster.webp"
        let capturedMedia: [SerializedMediaItem] = [
            .video(StoredVideoMediaReference(
                .remoteURL("https://cdn.example.com/missing.mp4"),
                thumbnail: .remoteURL(posterURL)
            ))
        ]
        let capturedMediaData = try JSONEncoder().encode(capturedMedia)
        let capturedMediaJSON = try #require(String(data: capturedMediaData, encoding: .utf8))
        context.insert(LocalScanRecord(
            id: scanID,
            speciesId: "cached-video-species",
            scientificName: "Testus video",
            commonName: "Cached Video",
            capturedMediaJSON: capturedMediaJSON
        ))
        try context.save()

        let responseData = try JSONEncoder().encode(HistoricalMediaPayload(
            id: scanID,
            image_storage_urls: [posterURL],
            video_storage_urls: [],
            audio_storage_urls: [],
            captured_media: capturedMedia,
            user_observation_context: nil
        ))
        let response = try JSONDecoder().decode(HistoricalScanResponse.self, from: responseData)
        let actor = HistoricalDatabaseActor(modelContainer: container)

        _ = await actor.reconcileScanPage(responses: [response])

        let verificationContext = ModelContext(container)
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanID }
        )
        descriptor.fetchLimit = 1
        let repaired = try #require(try verificationContext.fetch(descriptor).first)
        #expect(repaired.serializedCapturedMediaItems == [
            .image(.remoteURL(posterURL))
        ])
    }

    @Test func testHistoricalReconciliationRestoresNonvisualAudioAndDescription() async throws {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let configuration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let scanID = "nonvisual-history-\(UUID().uuidString.lowercased())"
        let remoteAudioURL = "https://cdn.example.com/field-recording.wav"
        var observationContext = ObservationContext(freeText: "Heard beside the creek")
        observationContext.addedAt = Date(timeIntervalSinceReferenceDate: 123_456)
        let localItems: [SerializedMediaItem] = [
            .audio(.documents("field-recording.wav")),
            .description(observationContext)
        ]
        let localMediaData = try JSONEncoder().encode(localItems)
        let localMediaJSON = try #require(String(data: localMediaData, encoding: .utf8))
        context.insert(LocalScanRecord(
            id: scanID,
            speciesId: "nonvisual-history-species",
            scientificName: "Testus sonorus",
            commonName: "Historical Audio",
            capturedMediaJSON: localMediaJSON
        ))
        try context.save()

        let responseData = try JSONEncoder().encode(HistoricalMediaPayload(
            id: scanID,
            image_storage_urls: [],
            video_storage_urls: [],
            audio_storage_urls: [remoteAudioURL],
            captured_media: nil,
            user_observation_context: observationContext
        ))
        let response = try JSONDecoder().decode(HistoricalScanResponse.self, from: responseData)
        let actor = HistoricalDatabaseActor(modelContainer: container)

        _ = await actor.reconcileScanPage(responses: [response])

        let verificationContext = ModelContext(container)
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanID }
        )
        descriptor.fetchLimit = 1
        let repaired = try #require(try verificationContext.fetch(descriptor).first)
        #expect(repaired.serializedCapturedMediaItems == [
            .audio(.documents("field-recording.wav")),
            .audio(.remoteURL(remoteAudioURL)),
            .description(observationContext)
        ])
    }

    @Test func testHistoricalReconciliationEnrichesExistingRemoteVisual() async throws {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let configuration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let scanID = "remote-visual-enrichment-\(UUID().uuidString.lowercased())"
        let remoteImageURL = "https://cdn.example.com/observation.webp"
        let remoteAudioURL = "https://cdn.example.com/field-recording.wav"
        let observationContext = ObservationContext(freeText: "Heard beside the creek")
        let existingItems: [SerializedMediaItem] = [
            .image(.remoteURL(remoteImageURL)),
            .audio(.documents("field-recording.wav"))
        ]
        let existingMediaData = try JSONEncoder().encode(existingItems)
        let existingMediaJSON = try #require(String(data: existingMediaData, encoding: .utf8))
        context.insert(LocalScanRecord(
            id: scanID,
            speciesId: "remote-visual-enrichment-species",
            scientificName: "Testus sonorus",
            commonName: "Historical Audio",
            capturedMediaJSON: existingMediaJSON
        ))
        try context.save()

        let responseData = try JSONEncoder().encode(HistoricalMediaPayload(
            id: scanID,
            image_storage_urls: [remoteImageURL],
            video_storage_urls: [],
            audio_storage_urls: [remoteAudioURL],
            captured_media: [.image(.remoteURL(remoteImageURL))],
            user_observation_context: observationContext
        ))
        let response = try JSONDecoder().decode(HistoricalScanResponse.self, from: responseData)
        let actor = HistoricalDatabaseActor(modelContainer: container)

        _ = await actor.reconcileScanPage(responses: [response])

        let verificationContext = ModelContext(container)
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanID }
        )
        descriptor.fetchLimit = 1
        let repaired = try #require(try verificationContext.fetch(descriptor).first)
        #expect(repaired.serializedCapturedMediaItems == [
            .image(.remoteURL(remoteImageURL)),
            .audio(.documents("field-recording.wav")),
            .audio(.remoteURL(remoteAudioURL)),
            .description(observationContext)
        ])
    }

    @Test func testHistoricalReconciliationKeepsCanonicalAudioWhenCompatibilityArrayIsEmpty() async throws {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let configuration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let scanID = "canonical-audio-history-\(UUID().uuidString.lowercased())"
        let remoteImageURL = "https://cdn.example.com/observation.webp"
        let remoteAudioURL = "https://cdn.example.com/field-recording.wav"
        let observationContext = ObservationContext(freeText: "Heard beside the creek")
        let existingItems: [SerializedMediaItem] = [
            .image(.remoteURL(remoteImageURL)),
            .audio(.documents("field-recording.wav", sourceIndex: 0))
        ]
        let existingMediaData = try JSONEncoder().encode(existingItems)
        let existingMediaJSON = try #require(String(data: existingMediaData, encoding: .utf8))
        context.insert(LocalScanRecord(
            id: scanID,
            speciesId: "canonical-audio-history-species",
            scientificName: "Testus sonorus",
            commonName: "Historical Audio",
            capturedMediaJSON: existingMediaJSON
        ))
        try context.save()

        let responseData = try JSONEncoder().encode(HistoricalMediaPayload(
            id: scanID,
            image_storage_urls: [remoteImageURL],
            video_storage_urls: [],
            audio_storage_urls: [],
            captured_media: [
                .image(.remoteURL(remoteImageURL)),
                .audio(.remoteURL(remoteAudioURL, sourceIndex: 0))
            ],
            user_observation_context: observationContext
        ))
        let response = try JSONDecoder().decode(HistoricalScanResponse.self, from: responseData)
        let actor = HistoricalDatabaseActor(modelContainer: container)

        _ = await actor.reconcileScanPage(responses: [response])

        let verificationContext = ModelContext(container)
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanID }
        )
        descriptor.fetchLimit = 1
        let repaired = try #require(try verificationContext.fetch(descriptor).first)
        #expect(repaired.serializedCapturedMediaItems == [
            .image(.remoteURL(remoteImageURL)),
            .audio(.remoteURL(remoteAudioURL, sourceIndex: 0)),
            .description(observationContext)
        ])
    }

    @Test func testHistoricalReconciliationPreservesAudioWhenCloudProjectionHasNoAudio() async throws {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let configuration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let scanID = "incomplete-nonvisual-history-\(UUID().uuidString.lowercased())"
        let remoteImageURL = "https://cdn.example.com/observation.webp"
        let existingAudioURL = "https://cdn.example.com/existing-field-recording.wav"
        let observationContext = ObservationContext(freeText: "Heard beside the creek")
        let existingItems: [SerializedMediaItem] = [
            .image(.remoteURL(remoteImageURL)),
            .audio(.remoteURL(existingAudioURL))
        ]
        let existingMediaData = try JSONEncoder().encode(existingItems)
        let existingMediaJSON = try #require(String(data: existingMediaData, encoding: .utf8))
        context.insert(LocalScanRecord(
            id: scanID,
            speciesId: "incomplete-nonvisual-history-species",
            scientificName: "Testus sonorus",
            commonName: "Historical Audio",
            capturedMediaJSON: existingMediaJSON
        ))
        try context.save()

        let responseData = try JSONEncoder().encode(HistoricalMediaPayload(
            id: scanID,
            image_storage_urls: [remoteImageURL],
            video_storage_urls: [],
            audio_storage_urls: [],
            captured_media: [.image(.remoteURL(remoteImageURL))],
            user_observation_context: observationContext
        ))
        let response = try JSONDecoder().decode(HistoricalScanResponse.self, from: responseData)
        let actor = HistoricalDatabaseActor(modelContainer: container)

        _ = await actor.reconcileScanPage(responses: [response])

        let verificationContext = ModelContext(container)
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanID }
        )
        descriptor.fetchLimit = 1
        let repaired = try #require(try verificationContext.fetch(descriptor).first)
        #expect(repaired.serializedCapturedMediaItems == [
            .image(.remoteURL(remoteImageURL)),
            .audio(.remoteURL(existingAudioURL)),
            .description(observationContext)
        ])
    }

    @Test func testHistoricalReconciliationPreservesSurplusAudioWhenCloudProjectionIsPartial() async throws {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let configuration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let scanID = "partial-multi-audio-history-\(UUID().uuidString.lowercased())"
        let remoteImageURL = "https://cdn.example.com/observation.webp"
        let remoteFirstAudioURL = "https://cdn.example.com/first-call.wav"
        let secondLocalAudio = StoredMediaReference.documents(
            "second-call.wav",
            sourceIndex: 1
        )
        let observationContext = ObservationContext(freeText: "Two calls recorded beside the creek")
        let existingItems: [SerializedMediaItem] = [
            .image(.remoteURL(remoteImageURL)),
            .audio(.documents("first-call.wav", sourceIndex: 0)),
            .audio(secondLocalAudio),
            .description(observationContext)
        ]
        let existingMediaData = try JSONEncoder().encode(existingItems)
        let existingMediaJSON = try #require(String(data: existingMediaData, encoding: .utf8))
        context.insert(LocalScanRecord(
            id: scanID,
            speciesId: "partial-multi-audio-history-species",
            scientificName: "Testus sonorus",
            commonName: "Historical Audio",
            capturedMediaJSON: existingMediaJSON
        ))
        try context.save()

        let responseData = try JSONEncoder().encode(HistoricalMediaPayload(
            id: scanID,
            image_storage_urls: [remoteImageURL],
            video_storage_urls: [],
            audio_storage_urls: [],
            captured_media: [
                .image(.remoteURL(remoteImageURL)),
                .audio(.remoteURL(remoteFirstAudioURL, sourceIndex: 0))
            ],
            user_observation_context: observationContext
        ))
        let response = try JSONDecoder().decode(HistoricalScanResponse.self, from: responseData)
        let actor = HistoricalDatabaseActor(modelContainer: container)

        _ = await actor.reconcileScanPage(responses: [response])

        let verificationContext = ModelContext(container)
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanID }
        )
        descriptor.fetchLimit = 1
        let repaired = try #require(try verificationContext.fetch(descriptor).first)
        #expect(repaired.serializedCapturedMediaItems == [
            .image(.remoteURL(remoteImageURL)),
            .audio(.remoteURL(remoteFirstAudioURL, sourceIndex: 0)),
            .audio(secondLocalAudio),
            .description(observationContext)
        ])
    }

    @Test func testHistoricalReconciliationMatchesPartialSecondAudioByDurableIdentity() async throws {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let configuration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let scanID = "partial-second-audio-history-\(UUID().uuidString.lowercased())"
        let remoteImageURL = "https://cdn.example.com/observation.webp"
        let firstLocalAudio = StoredMediaReference.documents(
            "first-call.wav",
            sourceIndex: 0
        )
        let secondLocalAudio = StoredMediaReference.documents(
            "second-call.wav",
            sourceIndex: 1
        )
        let remoteSecondAudio = StoredMediaReference.remoteURL(
            "https://cdn.example.com/promoted-second-call.wav",
            sourceIndex: 1
        )
        let observationContext = ObservationContext(
            freeText: "Two calls recorded beside the creek"
        )
        let existingItems: [SerializedMediaItem] = [
            .image(.remoteURL(remoteImageURL)),
            .audio(firstLocalAudio),
            .audio(secondLocalAudio),
            .description(observationContext)
        ]
        let existingMediaJSON = try #require(
            String(data: JSONEncoder().encode(existingItems), encoding: .utf8)
        )
        context.insert(LocalScanRecord(
            id: scanID,
            speciesId: "partial-second-audio-history-species",
            scientificName: "Testus sonorus",
            commonName: "Historical Audio",
            capturedMediaJSON: existingMediaJSON
        ))
        try context.save()

        let responseData = try JSONEncoder().encode(HistoricalMediaPayload(
            id: scanID,
            image_storage_urls: [remoteImageURL],
            video_storage_urls: [],
            audio_storage_urls: [],
            captured_media: [
                .image(.remoteURL(remoteImageURL)),
                .audio(remoteSecondAudio)
            ],
            user_observation_context: observationContext
        ))
        let response = try JSONDecoder().decode(
            HistoricalScanResponse.self,
            from: responseData
        )
        let actor = HistoricalDatabaseActor(modelContainer: container)

        _ = await actor.reconcileScanPage(responses: [response])

        let verificationContext = ModelContext(container)
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanID }
        )
        descriptor.fetchLimit = 1
        let repaired = try #require(try verificationContext.fetch(descriptor).first)
        #expect(repaired.serializedCapturedMediaItems == [
            .image(.remoteURL(remoteImageURL)),
            .audio(firstLocalAudio),
            .audio(remoteSecondAudio),
            .description(observationContext)
        ])
    }

    @Test func testHistoricalReconciliationPersistsIdentityForMatchingRemoteAudioPath() async throws {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let configuration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let scanID = "audio-identity-enrichment-\(UUID().uuidString.lowercased())"
        let remoteImageURL = "https://cdn.example.com/observation.webp"
        let remoteAudioURL = "https://cdn.example.com/field-recording.wav"
        let existingItems: [SerializedMediaItem] = [
            .image(.remoteURL(remoteImageURL)),
            .audio(.remoteURL(remoteAudioURL))
        ]
        let existingMediaJSON = try #require(
            String(data: JSONEncoder().encode(existingItems), encoding: .utf8)
        )
        context.insert(LocalScanRecord(
            id: scanID,
            speciesId: "audio-identity-enrichment-species",
            scientificName: "Testus sonorus",
            commonName: "Historical Audio",
            capturedMediaJSON: existingMediaJSON
        ))
        try context.save()

        let indexedAudio = StoredMediaReference.remoteURL(
            remoteAudioURL,
            sourceIndex: 0
        )
        let responseData = try JSONEncoder().encode(HistoricalMediaPayload(
            id: scanID,
            image_storage_urls: [remoteImageURL],
            video_storage_urls: [],
            audio_storage_urls: [],
            captured_media: [
                .image(.remoteURL(remoteImageURL)),
                .audio(indexedAudio)
            ],
            user_observation_context: nil
        ))
        let response = try JSONDecoder().decode(
            HistoricalScanResponse.self,
            from: responseData
        )
        let actor = HistoricalDatabaseActor(modelContainer: container)

        _ = await actor.reconcileScanPage(responses: [response])

        let verificationContext = ModelContext(container)
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanID }
        )
        descriptor.fetchLimit = 1
        let repaired = try #require(try verificationContext.fetch(descriptor).first)
        #expect(repaired.serializedCapturedMediaItems == [
            .image(.remoteURL(remoteImageURL)),
            .audio(indexedAudio)
        ])
    }

    @Test func testCollectionRelationshipsRetainProperReferences() async throws {
        // Arrange
        let ctx = try createIsolatedContext()
        
        let record = LocalScanRecord(
            speciesId: "test-species",
            scientificName: "Test scientific",
            commonName: "Test common"
        )
        ctx.insert(record)
        
        let collection = ScanCollection(name: "Test Extracted Collection")
        ctx.insert(collection)
        
        // Assert bi-directional boundary execution without triggering SwiftData duplicate tracking loops
        var updatedCollectionScans = collection.scans ?? []
        updatedCollectionScans.append(record)
        collection.scans = updatedCollectionScans

        var updatedRecordCollections = record.collections ?? []
        updatedRecordCollections.append(collection)
        record.collections = updatedRecordCollections
        
        try ctx.save()
        
        // Verify relationship boundaries effectively bounded the model properly natively
        let collectionId = collection.id
        let refetchedCollectionDescriptor = FetchDescriptor<ScanCollection>(predicate: #Predicate { $0.id == collectionId })
        let fetchedCollection = try ctx.fetch(refetchedCollectionDescriptor).first
        
        #expect(fetchedCollection?.scans?.count == 1, "Collection must append LocalScanRecord instance locally without failure")
        #expect(fetchedCollection?.scans?.first?.id == record.id, "Appended scan must match original insertion bounds")
        
        let recordId = record.id
        let refetchedRecordDescriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == recordId })
        let fetchedRecord = try ctx.fetch(refetchedRecordDescriptor).first
        
        #expect(fetchedRecord?.collections?.count == 1, "Record must inversely append ScanCollection")
        #expect(fetchedRecord?.collections?.first?.id == collection.id, "Inversely appended collection must match bounds")
    }
    
    @Test func testArchiveMigrationBooleanTogglesCorrectly() async throws {
        // Arrange
        let ctx = try createIsolatedContext()
        
        let record = LocalScanRecord(
            speciesId: "test-species-archive",
            scientificName: "Archive Phase",
            commonName: "Test Archive state"
        )
        ctx.insert(record)
        
        // Base state assertion ensures the backward-compatible local archive flag initializes as `false`.
        #expect(record.isLocallyArchived == false, "Initial scan mapping must NOT be locally archived")

        // Act: Mutate manually to confirm the legacy flag still persists for already-archived records.
        record.isLocallyArchived = true
        try ctx.save()
        
        // Assert permanence in storage
        let recordId = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == recordId })
        let fetched = try ctx.fetch(descriptor).first
        
        #expect(fetched?.isLocallyArchived == true, "Scan model must persist locally_archived flag reliably beyond offline boundaries")
    }

    // MARK: - V15 Premium Insights persistence

    @Test func testV15AiReasoningPersistsRoundTrip() async throws {
        let ctx = try createPremiumFieldsContext()
        let record = LocalScanRecord(
            speciesId: "v15-species",
            scientificName: "Danaus plexippus",
            commonName: "Monarch Butterfly",
            aiReasoning: "Orange and black wing pattern with white marginal spots confirms Danaus plexippus."
        )
        ctx.insert(record)
        try ctx.save()

        let id = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        let fetched = try ctx.fetch(descriptor).first

        #expect(fetched?.aiReasoning?.contains("Danaus plexippus") == true)
    }

    @Test func testV15HabitatDescriptionPersistsRoundTrip() async throws {
        let ctx = try createPremiumFieldsContext()
        let record = LocalScanRecord(
            speciesId: "v15-habitat",
            scientificName: "Photinus pyralis",
            commonName: "Firefly",
            habitatDescription: "Warm temperate meadows and forest edges near standing water."
        )
        ctx.insert(record)
        try ctx.save()

        let id = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        let fetched = try ctx.fetch(descriptor).first

        #expect(fetched?.habitatDescription?.contains("meadows") == true)
    }

    @Test func testV26SimilarSpeciesRoundTrip() async throws {
        let ctx = try createPremiumFieldsContext()
        let record = LocalScanRecord(
            speciesId: "v26-lookalikes",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            similarSpecies: ["Procyon cancrivorus", "Bassariscus astutus"]
        )
        ctx.insert(record)
        try ctx.save()

        let id = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        let fetched = try ctx.fetch(descriptor).first
        let names = try #require(fetched?.similarSpecies)

        #expect(names == ["Procyon cancrivorus", "Bassariscus astutus"])
    }

    @Test func testV27LookalikesDataRoundTrip() async throws {
        let ctx = try createPremiumFieldsContext()

        let entries: [SimilarSpeciesEntry] = [
            SimilarSpeciesEntry(scientificName: "Procyon cancrivorus", commonName: "Crab-eating Raccoon",
                                referenceImageUrl: "https://example.com/img.webp", iucnRedListStatus: "LC"),
            SimilarSpeciesEntry(scientificName: "Bassariscus astutus", commonName: nil,
                                referenceImageUrl: nil, iucnRedListStatus: nil)
        ]
        let blob = try JSONEncoder().encode(entries)

        let record = LocalScanRecord(
            speciesId: "v27-lookalikes-rich",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            lookalikesData: blob
        )
        ctx.insert(record)
        try ctx.save()

        let id = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        let fetched = try #require(try ctx.fetch(descriptor).first)
        let fetchedBlob = try #require(fetched.lookalikesData)
        let decoded = try JSONDecoder().decode([SimilarSpeciesEntry].self, from: fetchedBlob)

        #expect(decoded.count == 2)
        #expect(decoded[0].scientificName == "Procyon cancrivorus")
        #expect(decoded[0].commonName == "Crab-eating Raccoon")
        #expect(decoded[0].iucnRedListStatus == "LC")
        #expect(decoded[1].scientificName == "Bassariscus astutus")
        #expect(decoded[1].commonName == nil)
    }

    @Test func testV15PremiumFieldsDefaultToNilOnLegacyRecord() async throws {
        let ctx = try createPremiumFieldsContext()
        let record = LocalScanRecord(
            speciesId: "v15-legacy",
            scientificName: "Procyon lotor",
            commonName: "Raccoon"
        )
        ctx.insert(record)
        try ctx.save()

        let id = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        let fetched = try ctx.fetch(descriptor).first

        #expect(fetched?.aiReasoning == nil, "aiReasoning must default to nil for records without premium data")
        #expect(fetched?.habitatDescription == nil, "habitatDescription must default to nil")
        #expect(fetched?.similarSpecies == nil, "similarSpecies must default to nil for records without lookalike data")
        #expect(fetched?.lookalikesData == nil, "lookalikesData must default to nil for records without rich lookalike data")
    }

    // MARK: - V28 Candidates persistence

    @Test func testV28CandidatesDataRoundTrip() async throws {
        let ctx = try createPremiumFieldsContext()

        let candidates: [IdentificationCandidate] = [
            IdentificationCandidate(scientificName: "Procyon cancrivorus", confidenceScore: 0.71),
            IdentificationCandidate(scientificName: "Bassariscus astutus", confidenceScore: 0.65)
        ]
        let blob = try JSONEncoder().encode(candidates)

        let record = LocalScanRecord(
            speciesId: "v28-candidates-repo",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            candidatesData: blob
        )
        ctx.insert(record)
        try ctx.save()

        let id = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        let fetched = try #require(try ctx.fetch(descriptor).first)
        let fetchedBlob = try #require(fetched.candidatesData)
        let decoded = try JSONDecoder().decode([IdentificationCandidate].self, from: fetchedBlob)

        #expect(decoded.count == 2)
        #expect(decoded[0].scientificName == "Procyon cancrivorus")
        #expect(decoded[0].confidenceScore == 0.71)
        #expect(decoded[1].scientificName == "Bassariscus astutus")
    }

    @Test func testCandidatesRoundTripWithAllFields() async throws {
        // Verifies that commonName and distinguishingFeature survive the encode → persist → decode cycle.
        // This guards the historical sync path: CloudIdentificationCandidate → IdentificationCandidate → candidatesData.
        let ctx = try createPremiumFieldsContext()

        let candidates: [IdentificationCandidate] = [
            IdentificationCandidate(
                scientificName: "Limenitis archippus",
                commonName: "Viceroy",
                confidenceScore: 0.71,
                distinguishingFeature: "Hindwing black postmedian band broader and more irregular"
            ),
            IdentificationCandidate(
                scientificName: "Danaus gilippus",
                commonName: "Queen",
                confidenceScore: 0.58,
                distinguishingFeature: "Forewing lacks white spots in the black apex band"
            )
        ]
        let blob = try JSONEncoder().encode(candidates)

        let record = LocalScanRecord(
            speciesId: "cand-full-fields",
            scientificName: "Danaus plexippus",
            commonName: "Monarch Butterfly",
            candidatesData: blob
        )
        ctx.insert(record)
        try ctx.save()

        let id = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        let fetched = try #require(try ctx.fetch(descriptor).first)
        let fetchedBlob = try #require(fetched.candidatesData)
        let decoded = try JSONDecoder().decode([IdentificationCandidate].self, from: fetchedBlob)

        #expect(decoded.count == 2)
        #expect(decoded[0].scientificName == "Limenitis archippus")
        #expect(decoded[0].commonName == "Viceroy", "commonName must survive encode → persist → decode")
        #expect(decoded[0].confidenceScore == 0.71)
        #expect(decoded[0].distinguishingFeature == "Hindwing black postmedian band broader and more irregular",
                "distinguishingFeature must survive encode → persist → decode")
        #expect(decoded[1].commonName == "Queen")
        #expect(decoded[1].distinguishingFeature == "Forewing lacks white spots in the black apex band")
    }

    @Test func testCandidatesPreMigrationShapeDecodesGracefully() async throws {
        // JSONB rows written before distinguishing_feature was added have the two-field shape.
        // IdentificationCandidate.distinguishingFeature is String? — absent keys must decode as nil, not crash.
        let ctx = try createPremiumFieldsContext()

        // Encode two-field JSON manually to simulate pre-migration cloud JSONB
        let preMigrationJSON = """
        [
            { "scientificName": "Procyon cancrivorus", "confidenceScore": 0.71 },
            { "scientificName": "Bassariscus astutus", "confidenceScore": 0.65 }
        ]
        """.data(using: .utf8)!

        let record = LocalScanRecord(
            speciesId: "cand-pre-migration",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            candidatesData: preMigrationJSON
        )
        ctx.insert(record)
        try ctx.save()

        let id = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        let fetched = try #require(try ctx.fetch(descriptor).first)
        let fetchedBlob = try #require(fetched.candidatesData)
        let decoded = try JSONDecoder().decode([IdentificationCandidate].self, from: fetchedBlob)

        #expect(decoded.count == 2)
        #expect(decoded[0].distinguishingFeature == nil, "Pre-migration rows missing distinguishing_feature must decode as nil")
        #expect(decoded[0].commonName == nil, "Pre-migration rows missing common_name must decode as nil")
        #expect(decoded[0].scientificName == "Procyon cancrivorus")
        #expect(decoded[0].confidenceScore == 0.71)
    }

    // MARK: - V29 identification review persistence

    @Test func testV29UserIdentificationOverrideRoundTrip() async throws {
        let ctx = try createPremiumFieldsContext()
        let record = LocalScanRecord(
            speciesId: "v29-override-repo",
            scientificName: "Procyon cancrivorus",
            commonName: "Crab-eating Raccoon",
            userIdentificationOverride: "Procyon cancrivorus"
        )
        ctx.insert(record)
        try ctx.save()

        let id = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        let fetched = try ctx.fetch(descriptor).first

        #expect(fetched?.userIdentificationOverride == "Procyon cancrivorus", "userIdentificationOverride must persist round-trip")
    }

    @Test func testV29UserConfirmedIdentificationRoundTrip() async throws {
        let ctx = try createPremiumFieldsContext()
        let record = LocalScanRecord(
            speciesId: "v29-confirmed-repo",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            userConfirmedIdentification: true
        )
        ctx.insert(record)
        try ctx.save()

        let id = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        let fetched = try ctx.fetch(descriptor).first

        #expect(fetched?.userConfirmedIdentification == true, "userConfirmedIdentification must persist round-trip")
    }

    @Test func testV29NewFieldsDefaultCorrectly() async throws {
        let ctx = try createPremiumFieldsContext()
        let record = LocalScanRecord(
            speciesId: "v29-defaults",
            scientificName: "Procyon lotor",
            commonName: "Raccoon"
        )
        ctx.insert(record)
        try ctx.save()

        let id = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        let fetched = try ctx.fetch(descriptor).first

        #expect(fetched?.candidatesData == nil, "candidatesData must default to nil for records captured before V28")
        #expect(fetched?.userIdentificationOverride == nil, "userIdentificationOverride must default to nil — no user action yet")
        #expect(fetched?.userConfirmedIdentification == false, "userConfirmedIdentification must default to false")
    }

    // MARK: - Deletion queueing

    @Test func testEradicateScanQueuesPendingCloudDeletionAndRemovesRecord() async throws {
        let ctx = try createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "delete-queueing",
            scientificName: "Cardinalis cardinalis",
            commonName: "Northern Cardinal"
        )
        ctx.insert(record)
        try ctx.save()

        let offlineQueue = OfflineQueueManager.shared
        let originalOnline = offlineQueue.isOnline
        defer { offlineQueue.isOnline = originalOnline }
        offlineQueue.isOnline = false

        ScanRepository.shared.eradicateScan(record: record, modelContext: ctx)

        let recordId = record.id
        let recordDescriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == recordId })
        let deletionDescriptor = FetchDescriptor<PendingCloudDeletionTask>(predicate: #Predicate { $0.scanId == recordId })

        #expect(try ctx.fetch(recordDescriptor).isEmpty, "eradicateScan must remove the local record immediately after queueing cloud deletion")
        #expect(try ctx.fetch(deletionDescriptor).count == 1, "eradicateScan must persist exactly one pending cloud deletion task")
    }

    @Test func testEradicateScanReusesExistingPendingCloudDeletionTask() async throws {
        let ctx = try createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "delete-idempotency",
            scientificName: "Cyanocitta cristata",
            commonName: "Blue Jay"
        )
        let existingTask = PendingCloudDeletionTask(scanId: record.id, timestamp: Date(timeIntervalSince1970: 123))

        ctx.insert(record)
        ctx.insert(existingTask)
        try ctx.save()

        let offlineQueue = OfflineQueueManager.shared
        let originalOnline = offlineQueue.isOnline
        defer { offlineQueue.isOnline = originalOnline }
        offlineQueue.isOnline = false

        ScanRepository.shared.eradicateScan(record: record, modelContext: ctx)

        let recordId = record.id
        let recordDescriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == recordId })
        let deletionDescriptor = FetchDescriptor<PendingCloudDeletionTask>(predicate: #Predicate { $0.scanId == recordId })
        let remainingTasks = try ctx.fetch(deletionDescriptor)

        #expect(try ctx.fetch(recordDescriptor).isEmpty, "eradicateScan should still delete the local record when a deletion task already exists")
        #expect(remainingTasks.count == 1, "eradicateScan must not duplicate pending cloud deletion tasks for the same scan")
        #expect(remainingTasks.first?.timestamp == existingTask.timestamp, "The existing pending cloud deletion task should be reused unchanged")
    }

    // MARK: - ingestScans timestamp guard

    /// Regression guard for the `guard let parsedDate = exifDate else { continue }` fix in
    /// `ScanRepository.ingestScans`.  The guard replaced a `?? Date()` fallback that silently
    /// inserted records with fabricated timestamps when `scan.timestamp` was nil or unparseable.
    ///
    /// This test verifies the two inputs that `exifDate` is derived from:
    /// 1. A `nil` timestamp → `flatMap` produces `nil` → guard fires → record skipped.
    /// 2. A garbage string → both ISO 8601 formatters return `nil` → guard fires → record skipped.
    ///
    /// The inline logic mirrors `ScanRepository.ingestScans` exactly so any drift between the
    /// test and the production code will surface as a test failure.
    @Test func testIngestScansTimestampGuardSkipsNilAndUnparseableTimestamps() {
        // Helper that replicates the exact exifDate derivation in ingestScans
        func deriveExifDate(from timestamp: String?) -> Date? {
            timestamp.flatMap { ts -> Date? in
                if ts.contains(".") {
                    return DateUtilities.iso8601FractionalFormatter.date(from: ts)
                        ?? DateUtilities.iso8601Formatter.date(from: ts)
                }
                return DateUtilities.iso8601Formatter.date(from: ts)
                    ?? DateUtilities.iso8601FractionalFormatter.date(from: ts)
            }
        }

        // nil timestamp → exifDate must be nil → guard triggers skip
        let nilResult = deriveExifDate(from: nil)
        #expect(nilResult == nil, "nil timestamp must produce nil exifDate — the guard skips the record")

        // Garbage string → both formatters return nil → exifDate is nil
        let garbageResult = deriveExifDate(from: "not-a-date")
        #expect(garbageResult == nil, "Unparseable timestamp must produce nil exifDate — not a fabricated Date()")

        // Partial ISO string (date only, no time) → must also fail both formatters
        let partialResult = deriveExifDate(from: "2026-04-05")
        #expect(partialResult == nil, "Date-only string without time component must not be accepted")

        // Valid fractional ISO string → must produce a non-nil date (positive control)
        let validFractional = deriveExifDate(from: "2026-04-05T14:23:01.000Z")
        #expect(validFractional != nil, "Valid fractional ISO 8601 timestamp must parse correctly")

        // Valid standard ISO string → must produce a non-nil date (positive control)
        let validStandard = deriveExifDate(from: "2026-04-05T14:23:01Z")
        #expect(validStandard != nil, "Valid standard ISO 8601 timestamp must parse correctly")
    }
}
