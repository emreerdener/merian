import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
struct SpeciesObservationStatsViewModelTests {
    private enum StubError: Error {
        case failed
        case unexpected
    }

    @Test func loadNormalizesIdentityAndCombinesLocalAndPublicResults() async throws {
        let context = try createIsolatedContext()
        let speciesId = "1CF79982-E5EE-4E3D-8D65-274527E6AE01"
        var receivedLocalIdentity: (String, String?)?
        var receivedPublicIdentity: (String, String)?
        let local = localStats(month: 5, count: 2)
        let publicResult = publicStats(
            scientificName: "Danaus plexippus",
            month: 8,
            count: 10
        )
        let viewModel = SpeciesObservationStatsViewModel(
            dependencies: .init(
                loadLocalStats: { name, identifier, _, _ in
                    receivedLocalIdentity = (name, identifier)
                    return local
                },
                loadPublicStats: { identifier, name in
                    receivedPublicIdentity = (identifier, name)
                    return publicResult
                },
                publicErrorMessage: { _ in "Public failed" }
            )
        )

        await viewModel.load(
            speciesId: speciesId,
            scientificName: "  Danaus   plexippus ",
            modelContext: context
        )

        #expect(receivedLocalIdentity?.0 == "Danaus plexippus")
        #expect(receivedLocalIdentity?.1 == speciesId)
        #expect(receivedPublicIdentity?.0 == speciesId.lowercased())
        #expect(receivedPublicIdentity?.1 == "Danaus plexippus")
        #expect(viewModel.localStats == local)
        #expect(viewModel.publicStats == publicResult)
        #expect(viewModel.publicErrorMessage == nil)
        #expect(!viewModel.isLoading)
    }

    @Test func localFailureDoesNotBlockPublicBaseline() async throws {
        let context = try createIsolatedContext()
        let publicResult = publicStats(
            scientificName: "Danaus plexippus",
            month: 8,
            count: 10
        )
        let viewModel = SpeciesObservationStatsViewModel(
            dependencies: .init(
                loadLocalStats: { _, _, _, _ in throw StubError.failed },
                loadPublicStats: { _, _ in publicResult },
                publicErrorMessage: { _ in "Public failed" }
            )
        )

        await viewModel.load(
            speciesId: speciesId,
            scientificName: "Danaus plexippus",
            modelContext: context
        )

        #expect(viewModel.localStats.totalObservations == 0)
        #expect(viewModel.publicStats == publicResult)
        #expect(viewModel.publicErrorMessage == nil)
        #expect(viewModel.hasAnyData)
    }

    @Test func publicFailurePreservesLocalStatsAndSurfacesMessage() async throws {
        let context = try createIsolatedContext()
        let local = localStats(month: 5, count: 2)
        let viewModel = SpeciesObservationStatsViewModel(
            dependencies: .init(
                loadLocalStats: { _, _, _, _ in local },
                loadPublicStats: { _, _ in throw StubError.failed },
                publicErrorMessage: { _ in "Public failed" }
            )
        )

        await viewModel.load(
            speciesId: speciesId,
            scientificName: "Danaus plexippus",
            modelContext: context
        )

        #expect(viewModel.localStats == local)
        #expect(viewModel.publicStats == nil)
        #expect(viewModel.publicErrorMessage == "Public failed")
        #expect(viewModel.hasAnyData)
    }

    @Test func latePublicResponseCannotOverwriteNewSpecies() async throws {
        let context = try createIsolatedContext()
        var pendingFirstLoad: CheckedContinuation<
            SpeciesObservationStatsEntry,
            any Error
        >?
        let firstPublic = publicStats(
            scientificName: "Danaus plexippus",
            month: 5,
            count: 3
        )
        let secondPublic = publicStats(
            scientificName: "Danaus gilippus",
            month: 8,
            count: 7
        )
        let viewModel = SpeciesObservationStatsViewModel(
            dependencies: .init(
                loadLocalStats: { name, _, _, _ in
                    self.localStats(
                        month: name == "Danaus plexippus" ? 5 : 8,
                        count: name == "Danaus plexippus" ? 1 : 2
                    )
                },
                loadPublicStats: { _, name in
                    if name == "Danaus plexippus" {
                        return try await withCheckedThrowingContinuation {
                            pendingFirstLoad = $0
                        }
                    }
                    return secondPublic
                },
                publicErrorMessage: { _ in "Public failed" }
            )
        )

        let firstLoad = Task {
            await viewModel.load(
                speciesId: speciesId,
                scientificName: "Danaus plexippus",
                modelContext: context
            )
        }
        while pendingFirstLoad == nil {
            await Task.yield()
        }

        await viewModel.load(
            speciesId: speciesId,
            scientificName: "Danaus gilippus",
            modelContext: context
        )
        pendingFirstLoad?.resume(returning: firstPublic)
        await firstLoad.value

        #expect(viewModel.publicStats == secondPublic)
        #expect(viewModel.localStats.totalObservations == 2)
        #expect(!viewModel.isLoading)
    }

    @Test func changingSpeciesClearsPublishedStatsWhileReplacementLoads() async throws {
        let context = try createIsolatedContext()
        var pendingSecondLocalLoad: CheckedContinuation<
            SpeciesObservationLocalStats,
            any Error
        >?
        let firstLocal = localStats(month: 5, count: 3)
        let secondLocal = localStats(month: 8, count: 2)
        let firstPublic = publicStats(
            scientificName: "Danaus plexippus",
            month: 5,
            count: 8
        )
        let secondPublic = publicStats(
            scientificName: "Danaus gilippus",
            month: 8,
            count: 5
        )
        let viewModel = SpeciesObservationStatsViewModel(
            dependencies: .init(
                loadLocalStats: { name, _, _, _ in
                    if name == "Danaus gilippus" {
                        return try await withCheckedThrowingContinuation {
                            pendingSecondLocalLoad = $0
                        }
                    }
                    return firstLocal
                },
                loadPublicStats: { _, name in
                    name == "Danaus gilippus" ? secondPublic : firstPublic
                },
                publicErrorMessage: { _ in "Public failed" }
            )
        )

        await viewModel.load(
            speciesId: speciesId,
            scientificName: "Danaus plexippus",
            modelContext: context
        )

        let secondLoad = Task {
            await viewModel.load(
                speciesId: "5ad99ec2-901c-4b2d-a643-ad84b4845160",
                scientificName: "Danaus gilippus",
                modelContext: context
            )
        }
        while pendingSecondLocalLoad == nil {
            await Task.yield()
        }

        #expect(viewModel.localStats.totalObservations == 0)
        #expect(viewModel.publicStats == nil)
        #expect(viewModel.isLoading)

        pendingSecondLocalLoad?.resume(returning: secondLocal)
        await secondLoad.value

        #expect(viewModel.localStats == secondLocal)
        #expect(viewModel.publicStats == secondPublic)
        #expect(!viewModel.isLoading)
    }

    @Test func preCancelledValidLoadDoesNotClaimGenerationOwnership() async throws {
        let context = try createIsolatedContext()
        var localCallCount = 0
        var publicCallCount = 0
        let local = localStats(month: 5, count: 3)
        let publicResult = publicStats(
            scientificName: "Danaus plexippus",
            month: 5,
            count: 8
        )
        let viewModel = SpeciesObservationStatsViewModel(
            dependencies: .init(
                loadLocalStats: { _, _, _, _ in
                    localCallCount += 1
                    return local
                },
                loadPublicStats: { _, _ in
                    publicCallCount += 1
                    return publicResult
                },
                publicErrorMessage: { _ in "Public failed" }
            )
        )

        await viewModel.load(
            speciesId: speciesId,
            scientificName: "Danaus plexippus",
            modelContext: context
        )

        let cancelledLoad = Task {
            await viewModel.load(
                speciesId: "5ad99ec2-901c-4b2d-a643-ad84b4845160",
                scientificName: "Danaus gilippus",
                modelContext: context
            )
        }
        cancelledLoad.cancel()
        await cancelledLoad.value

        #expect(localCallCount == 1)
        #expect(publicCallCount == 1)
        #expect(viewModel.localStats == local)
        #expect(viewModel.publicStats == publicResult)
        #expect(!viewModel.isLoading)
    }

    @Test func emptyIdentityInvalidatesAnInFlightLoad() async throws {
        let context = try createIsolatedContext()
        var pendingLocalLoad: CheckedContinuation<
            SpeciesObservationLocalStats,
            any Error
        >?
        var publicCallCount = 0
        let viewModel = SpeciesObservationStatsViewModel(
            dependencies: .init(
                loadLocalStats: { _, _, _, _ in
                    try await withCheckedThrowingContinuation {
                        pendingLocalLoad = $0
                    }
                },
                loadPublicStats: { _, _ in
                    publicCallCount += 1
                    throw StubError.unexpected
                },
                publicErrorMessage: { _ in "Public failed" }
            )
        )

        let firstLoad = Task {
            await viewModel.load(
                speciesId: speciesId,
                scientificName: "Danaus plexippus",
                modelContext: context
            )
        }
        while pendingLocalLoad == nil {
            await Task.yield()
        }

        await viewModel.load(
            speciesId: speciesId,
            scientificName: "   ",
            modelContext: context
        )
        pendingLocalLoad?.resume(returning: localStats(month: 5, count: 4))
        await firstLoad.value

        #expect(viewModel.localStats.totalObservations == 0)
        #expect(viewModel.publicStats == nil)
        #expect(publicCallCount == 0)
        #expect(!viewModel.isLoading)
    }

    @Test func cancellationStopsAfterAnUncooperativeLocalLoad() async throws {
        let context = try createIsolatedContext()
        var pendingLocalLoad: CheckedContinuation<
            SpeciesObservationLocalStats,
            any Error
        >?
        var publicCallCount = 0
        let viewModel = SpeciesObservationStatsViewModel(
            dependencies: .init(
                loadLocalStats: { _, _, _, _ in
                    try await withCheckedThrowingContinuation {
                        pendingLocalLoad = $0
                    }
                },
                loadPublicStats: { _, _ in
                    publicCallCount += 1
                    throw StubError.unexpected
                },
                publicErrorMessage: { _ in "Public failed" }
            )
        )

        let load = Task {
            await viewModel.load(
                speciesId: speciesId,
                scientificName: "Danaus plexippus",
                modelContext: context
            )
        }
        while pendingLocalLoad == nil {
            await Task.yield()
        }

        load.cancel()
        pendingLocalLoad?.resume(returning: localStats(month: 5, count: 4))
        await load.value

        #expect(viewModel.localStats.totalObservations == 0)
        #expect(viewModel.publicStats == nil)
        #expect(publicCallCount == 0)
        #expect(!viewModel.isLoading)
    }

    @Test func missingSpeciesIdSkipsPublicLoading() async throws {
        let context = try createIsolatedContext()
        var publicCallCount = 0
        let local = localStats(month: 5, count: 1)
        let viewModel = SpeciesObservationStatsViewModel(
            dependencies: .init(
                loadLocalStats: { _, _, _, _ in local },
                loadPublicStats: { _, _ in
                    publicCallCount += 1
                    throw StubError.unexpected
                },
                publicErrorMessage: { _ in "Public failed" }
            )
        )

        await viewModel.load(
            speciesId: nil,
            scientificName: "Danaus plexippus",
            modelContext: context
        )

        #expect(viewModel.localStats == local)
        #expect(publicCallCount == 0)
        #expect(viewModel.publicStats == nil)
    }

    private var speciesId: String {
        "1cf79982-e5ee-4e3d-8d65-274527e6ae01"
    }

    private func createIsolatedContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        return ModelContext(container)
    }

    private func localStats(
        month: Int,
        count: Int
    ) -> SpeciesObservationLocalStats {
        SpeciesObservationLocalStats(
            seasonality: monthCounts([month: count]),
            history: [],
            lifeStage: [],
            totalObservations: count,
            lastObservationDate: nil
        )
    }

    private func publicStats(
        scientificName: String,
        month: Int,
        count: Int
    ) -> SpeciesObservationStatsEntry {
        SpeciesObservationStatsEntry(
            speciesId: speciesId,
            scientificName: scientificName,
            source: SpeciesObservationStatsSource(
                provider: "inaturalist",
                scope: "global",
                inaturalistTaxonId: nil,
                fetchedAt: "2026-08-31T00:00:00Z"
            ),
            status: .fresh,
            totalObservations: count,
            lastObservationDate: nil,
            fetchedAt: "2026-08-31T00:00:00Z",
            providerErrors: [],
            seasonality: monthCounts([month: count]),
            history: [],
            lifeStage: []
        )
    }

    private func monthCounts(
        _ countsByMonth: [Int: Int]
    ) -> [SpeciesObservationMonthCount] {
        (1...12).map { month in
            SpeciesObservationMonthCount(
                month: month,
                count: countsByMonth[month, default: 0]
            )
        }
    }
}
