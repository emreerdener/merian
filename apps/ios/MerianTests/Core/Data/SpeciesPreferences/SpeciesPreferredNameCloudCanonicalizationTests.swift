import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite("Species Preferred Name Cloud Canonicalization")
struct SpeciesNameCloudCanonicalizationTests {
    @Test func normalizedRemoteDuplicatesUseNewestValidRow() async throws {
        let context = try makeSpeciesPreferenceContext()
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let lease = makeSpeciesPreferenceLease()
        let client = SpeciesPreferredNameCloudClient(
            beginAccountWork: { lease },
            finishAccountWork: { _ in },
            isAccountWorkCurrent: { _ in true },
            fetchPage: { _, _, _ in
                [
                    makeSpeciesPreferenceCloudRow(
                        scientificName: " Quercus alba ",
                        preferredName: "Old White Oak",
                        updatedAt: "2026-08-01T12:00:00.000Z"
                    ),
                    makeSpeciesPreferenceCloudRow(
                        scientificName: "Quercus alba",
                        preferredName: "White Oak",
                        updatedAt: "2026-08-01T12:01:00.000Z"
                    )
                ]
            },
            upsert: { _ in }
        )
        let coordinator = SpeciesPreferredNameCloudSyncCoordinator(
            client: client
        )

        #expect(await coordinator.sync(
            modelContext: context,
            legacyDefaults: defaults,
            force: true
        ))
        #expect(
            try fetchSpeciesPreference(
                for: "Quercus alba",
                modelContext: context
            )?.preferredCommonName == "White Oak"
        )
    }

    @Test func normalizedLocalDuplicatesProduceOneNewestUpsert() async throws {
        let context = try makeSpeciesPreferenceContext()
        context.insert(
            UserSpeciesPreference(
                scientificName: " Quercus alba ",
                preferredCommonName: "Old White Oak",
                updatedAt: Date(timeIntervalSince1970: 1_000)
            )
        )
        context.insert(
            UserSpeciesPreference(
                scientificName: "Quercus alba",
                preferredCommonName: "White Oak",
                updatedAt: Date(timeIntervalSince1970: 2_000)
            )
        )
        try context.save()
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let lease = makeSpeciesPreferenceLease()
        var capturedUpserts: [SpeciesPreferenceCloudUpsert] = []
        let client = SpeciesPreferredNameCloudClient(
            beginAccountWork: { lease },
            finishAccountWork: { _ in },
            isAccountWorkCurrent: { _ in true },
            fetchPage: { _, _, _ in [] },
            upsert: { capturedUpserts = $0 }
        )
        let coordinator = SpeciesPreferredNameCloudSyncCoordinator(
            client: client
        )

        #expect(await coordinator.sync(
            modelContext: context,
            legacyDefaults: defaults,
            force: true
        ))
        #expect(capturedUpserts.count == 1)
        #expect(capturedUpserts.first?.scientific_name == "Quercus alba")
        #expect(capturedUpserts.first?.preferred_common_name == "White Oak")
    }
}
