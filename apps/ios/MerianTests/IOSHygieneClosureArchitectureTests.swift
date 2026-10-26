import Testing

@Suite("iOS Hygiene Closure Architecture")
struct IOSHygieneClosureArchitectureTests {
    @Test func sharedLineCountMatchesPhysicalLines() {
        #expect(DatabaseActorTestSupport.lineCount(of: "") == 0)
        #expect(DatabaseActorTestSupport.lineCount(of: "one") == 1)
        #expect(DatabaseActorTestSupport.lineCount(of: "one\n") == 1)
        #expect(DatabaseActorTestSupport.lineCount(of: "one\ntwo") == 2)
        #expect(DatabaseActorTestSupport.lineCount(of: "one\ntwo\n") == 2)
    }

    @Test func oversizedProductionOwnersRemainAnExplicitInventory() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: Self.productionDirectory
        )
        let oversizedOwners = Set(
            sources.compactMap { source -> String? in
                DatabaseActorTestSupport.lineCount(of: source.contents) > 600
                    ? source.relativePath
                    : nil
            }
        )

        #expect(oversizedOwners == Self.trackedOversizedOwners)
        for (path, ceiling) in Self.sealedOwnerCeilings {
            let source = try #require(sources.first { $0.relativePath == path })
            #expect(
                DatabaseActorTestSupport.lineCount(of: source.contents) <= ceiling,
                "\(path) exceeds its reviewed sealed-owner ceiling"
            )
        }
    }

    private static let productionDirectory = "apps/ios/Merian"

    // Keep capability minting and private fences together; no growth allowance.
    private static let sealedOwnerCeilings: [String: Int] = [
        "Core/Data/SharedMediaStorage/SharedMediaNativeOriginalOwner.swift": 610,
        "Core/Data/SharedMediaStorage/SharedMediaNativeStorageRepository.swift": 622
    ]

    private static let trackedOversizedOwners: Set<String> = [
        "Core/Data/SharedMediaStorage/SharedMediaNativeStorageRepository.swift",
        "App/UITesting/UITestSeedCoordinator.swift",
        // Versioned wire decoders are generator-owned and validated as one contract.
        "Core/AI/InferenceEdgeDTOs.swift",
        "Core/Network/SupabaseManager.swift",
        "Models/SchemaVersions.swift",
        // The immutable V51 model graph must remain together as its verified snapshot.
        "Models/Schema/SchemaV51Snapshots.swift"
    ]
}
