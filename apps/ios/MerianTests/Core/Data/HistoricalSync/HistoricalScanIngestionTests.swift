import Foundation
import SwiftData
import Testing

@testable import Merian

extension ScanRepositoryTests {
    @Test func testHistoricalAudioRehydrationPreservesSubjectClassification() async throws {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory
            .appendingPathComponent(UUID().uuidString + ".sqlite")
        let configuration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
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
            try decoder.decode(
                HistoricalScanResponse.self,
                from: Data($0.utf8)
            )
        }
        let actor = HistoricalDatabaseActor(modelContainer: container)

        let insertedCount = try await actor.reconcileScanPage(
            responses: responses
        )
        #expect(insertedCount == 3)

        let verificationContext = ModelContext(container)
        let records = try verificationContext.fetch(
            FetchDescriptor<LocalScanRecord>()
        )
        let recordsByID = Dictionary(
            uniqueKeysWithValues: records.map { ($0.id, $0) }
        )
        let nonBiological = try #require(
            recordsByID["historical-audio-nonbio"]
        )
        let unresolved = try #require(
            recordsByID["historical-audio-unresolved"]
        )
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

    @Test func historicalReconciliationCountsOnlyPersistedRows() async throws {
        let context = try ScanRepositoryTestSupport.makeContext()
        let actor = HistoricalDatabaseActor(
            modelContainer: context.container
        )
        let validId = "valid-historical-\(UUID().uuidString.lowercased())"
        let invalidId = "invalid-historical-\(UUID().uuidString.lowercased())"
        let payload = Data(
            """
            [
              {
                "id": "\(validId)",
                "timestamp": "2026-09-09T12:00:00.000Z"
              },
              {
                "id": "\(invalidId)",
                "timestamp": "not-a-date"
              }
            ]
            """.utf8
        )
        let responses = try JSONDecoder().decode(
            [HistoricalScanResponse].self,
            from: payload
        )

        let insertedCount = try await actor.reconcileScanPage(
            responses: responses
        )

        #expect(insertedCount == 1)
        let records = try ModelContext(context.container).fetch(
            FetchDescriptor<LocalScanRecord>()
        )
        #expect(records.map(\.id) == [validId])
    }

    @Test func testIngestScansTimestampGuardSkipsNilAndUnparseableTimestamps() async throws {
        let context = try ScanRepositoryTestSupport.makeContext()
        let actor = HistoricalDatabaseActor(
            modelContainer: context.container
        )
        let payload = Data(
            """
            [
              {"id":"missing-timestamp"},
              {"id":"invalid-timestamp","timestamp":"not-a-date"},
              {"id":"partial-timestamp","timestamp":"2026-04-05"},
              {
                "id":"fractional-timestamp",
                "timestamp":"2026-04-05T14:23:01.000Z"
              },
              {
                "id":"standard-timestamp",
                "timestamp":"2026-04-05T14:23:01Z"
              }
            ]
            """.utf8
        )
        let responses = try JSONDecoder().decode(
            [HistoricalScanResponse].self,
            from: payload
        )

        let insertedCount = try await actor.reconcileScanPage(
            responses: responses
        )
        let records = try ModelContext(context.container).fetch(
            FetchDescriptor<LocalScanRecord>()
        )

        #expect(insertedCount == 2)
        #expect(Set(records.map(\.id)) == [
            "fractional-timestamp",
            "standard-timestamp"
        ])
        #expect(records.allSatisfy { $0.captureDate != nil })
    }
}
