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
        let oversizedOwners = Set(
            try DatabaseActorTestSupport.swiftSources(
                below: Self.productionDirectory
            ).compactMap { source -> String? in
                DatabaseActorTestSupport.lineCount(of: source.contents) > 600
                    ? source.relativePath
                    : nil
            }
        )

        #expect(oversizedOwners == Self.trackedOversizedOwners)
    }

    private static let productionDirectory = "apps/ios/Merian"

    private static let trackedOversizedOwners: Set<String> = [
        "App/UITesting/UITestSeedCoordinator.swift",
        "Core/Network/SupabaseManager.swift",
        "Models/SchemaVersions.swift"
    ]
}
