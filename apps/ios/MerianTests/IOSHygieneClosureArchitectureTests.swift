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
        let policy = try IOSSourceSizePolicy.load(root: DatabaseActorTestSupport.repositoryRoot())
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: Self.productionDirectory
        )
        let oversizedOwners = Set(
            sources.compactMap { source -> String? in
                DatabaseActorTestSupport.lineCount(of: source.contents) > policy.globalCeiling
                    ? source.relativePath
                    : nil
            }
        )

        #expect(oversizedOwners == policy.oversizedOwners)
        for (path, ceiling) in policy.sealedOwnerCeilings {
            let source = try #require(sources.first { $0.relativePath == path })
            #expect(
                DatabaseActorTestSupport.lineCount(of: source.contents) <= ceiling,
                "\(path) exceeds its reviewed sealed-owner ceiling"
            )
        }
    }

    private static let productionDirectory = "apps/ios/Merian"

}
