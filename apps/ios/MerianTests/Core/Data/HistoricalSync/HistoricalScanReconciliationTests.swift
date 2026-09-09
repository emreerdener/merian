import Foundation
import SwiftData
import Testing

@testable import Merian

extension ScanRepositoryTests {
    private struct HistoricalMediaPayload: Encodable {
        let id: String
        let image_storage_urls: [String]
        let video_storage_urls: [String]
        let audio_storage_urls: [String]?
        let captured_media: [SerializedMediaItem]?
        let user_observation_context: ObservationContext?
    }

    @Test func cancelledCollectionReconciliationPreservesLocalRows() async throws {
        let context = try ScanRepositoryTestSupport.makeContext()
        let retainedCollection = ScanCollection(name: "Retained Collection")
        context.insert(retainedCollection)
        try context.save()
        let retainedId = retainedCollection.id

        let actor = HistoricalDatabaseActor(
            modelContainer: context.container
        )
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await actor.syncCollectionsDown(remoteCollections: [])
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        let verificationContext = ModelContext(context.container)
        let collections = try verificationContext.fetch(
            FetchDescriptor<ScanCollection>()
        )
        #expect(collections.map(\.id) == [retainedId])
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

        _ = try await actor.reconcileScanPage(responses: [response])

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
        let observationContext = ObservationContext(freeText: "Heard beside the creek")
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

        _ = try await actor.reconcileScanPage(responses: [response])

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

        _ = try await actor.reconcileScanPage(responses: [response])

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

        _ = try await actor.reconcileScanPage(responses: [response])

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

        _ = try await actor.reconcileScanPage(responses: [response])

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

        _ = try await actor.reconcileScanPage(responses: [response])

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

        _ = try await actor.reconcileScanPage(responses: [response])

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

        _ = try await actor.reconcileScanPage(responses: [response])

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
}
