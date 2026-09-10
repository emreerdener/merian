import SwiftData
import Testing

@testable import Merian

@Suite("Local Scan Media Recovery Registration")
struct ScanMediaRecoveryRegistrationTests {
    private enum RegistrationPhase: String, Sendable {
        case strongEvidence
        case timestamp
    }

    private actor RegistrationProbe {
        private(set) var calls: [(RegistrationPhase, [String])] = []

        func register(
            _ snapshots: [LocalScanMediaRecoverySnapshot],
            phase: RegistrationPhase
        ) -> Int {
            calls.append((phase, snapshots.map(\.scanID)))
            return snapshots.count
        }
    }

    @MainActor
    @Test func pagesTheStoreInStableBoundedBatches() async throws {
        let container = try makeContainer()
        let baseTimestamp = Date(timeIntervalSince1970: 1_700_000_000)
        for index in (0..<5).reversed() {
            container.mainContext.insert(
                LocalScanRecord(
                    id: "scan-\(index)",
                    speciesId: "species-\(index)",
                    scientificName: "Species \(index)",
                    commonName: "Subject \(index)",
                    timestamp: baseTimestamp.addingTimeInterval(
                        TimeInterval(index)
                    )
                )
            )
        }
        try container.mainContext.save()

        let probe = RegistrationProbe()
        let service = ScanMediaRecoveryRegistrationService(
            dependencies: .init(
                hasLegacyRecoveryIndex: { true },
                registerStrongEvidenceMappings: { snapshots in
                    await probe.register(snapshots, phase: .strongEvidence)
                },
                registerTimestampMappings: { snapshots in
                    await probe.register(snapshots, phase: .timestamp)
                }
            )
        )

        let registeredCount = try await service.registerMappings(
            in: container,
            batchSize: 2
        )

        #expect(registeredCount == 10)
        let calls = await probe.calls
        #expect(calls.map(\.0) == [
            .strongEvidence, .strongEvidence, .strongEvidence,
            .timestamp, .timestamp, .timestamp
        ])
        #expect(calls.map(\.1) == [
            ["scan-0", "scan-1"],
            ["scan-2", "scan-3"],
            ["scan-4"],
            ["scan-0", "scan-1"],
            ["scan-2", "scan-3"],
            ["scan-4"]
        ])
    }

    @MainActor
    @Test func skipsTheStoreWhenNoLegacyIndexExists() async throws {
        let container = try makeContainer()
        let probe = RegistrationProbe()
        let service = ScanMediaRecoveryRegistrationService(
            dependencies: .init(
                hasLegacyRecoveryIndex: { false },
                registerStrongEvidenceMappings: { snapshots in
                    await probe.register(snapshots, phase: .strongEvidence)
                },
                registerTimestampMappings: { snapshots in
                    await probe.register(snapshots, phase: .timestamp)
                }
            )
        )

        let registeredCount = try await service.registerMappings(
            in: container
        )

        #expect(registeredCount == nil)
        let calls = await probe.calls
        #expect(calls.isEmpty)
    }

    @MainActor
    @Test func capsOversizedBatchRequests() async throws {
        let container = try makeContainer()
        for index in 0..<201 {
            container.mainContext.insert(
                LocalScanRecord(
                    id: "bounded-scan-\(index)",
                    speciesId: "bounded-species-\(index)",
                    scientificName: "Bounded Species \(index)",
                    commonName: "Bounded Subject \(index)",
                    timestamp: Date(
                        timeIntervalSince1970: TimeInterval(index)
                    )
                )
            )
        }
        try container.mainContext.save()

        let probe = RegistrationProbe()
        let service = ScanMediaRecoveryRegistrationService(
            dependencies: .init(
                hasLegacyRecoveryIndex: { true },
                registerStrongEvidenceMappings: { snapshots in
                    await probe.register(snapshots, phase: .strongEvidence)
                },
                registerTimestampMappings: { snapshots in
                    await probe.register(snapshots, phase: .timestamp)
                }
            )
        )

        let registeredCount = try await service.registerMappings(
            in: container,
            batchSize: .max
        )

        #expect(registeredCount == 402)
        let calls = await probe.calls
        #expect(calls.map { $0.1.count } == [200, 1, 200, 1])
    }

    @MainActor
    @Test func cancellationStopsBeforeReadingOrRegistering() async throws {
        let container = try makeContainer()
        let probe = RegistrationProbe()
        let service = ScanMediaRecoveryRegistrationService(
            dependencies: .init(
                hasLegacyRecoveryIndex: { true },
                registerStrongEvidenceMappings: { snapshots in
                    await probe.register(snapshots, phase: .strongEvidence)
                },
                registerTimestampMappings: { snapshots in
                    await probe.register(snapshots, phase: .timestamp)
                }
            )
        )
        let task = Task { @MainActor in
            try await service.registerMappings(in: container)
        }

        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        let calls = await probe.calls
        #expect(calls.isEmpty)
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([LocalScanRecord.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }
}
