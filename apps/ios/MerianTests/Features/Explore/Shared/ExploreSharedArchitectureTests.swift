import Foundation
import Testing

@Suite("Explore Shared Architecture")
struct ExploreSharedArchitectureTests {
    @Test func errorPresentationHasOneExploreSharedOwner() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/Merian"
        )
        let owners = sources.compactMap { source in
            source.contents.contains("enum ExploreErrorFormatter")
                ? source.relativePath
                : nil
        }

        #expect(owners == [Self.errorFormatterPath])

        let source = try DatabaseActorTestSupport.loadRepositorySource(
            at: "apps/ios/Merian/\(Self.errorFormatterPath)"
        )
        #expect(imports(in: source) == ["import Foundation"])
        for effectToken in Self.forbiddenErrorPresentationEffects {
            #expect(
                !source.contains(effectToken),
                "ExploreErrorFormatter resolves \(effectToken)"
            )
        }
        #expect(DatabaseActorTestSupport.lineCount(of: source) <= 600)
    }

    @Test func errorPresentationTestsMirrorTheFeatureOwner() throws {
        let repository = try DatabaseActorTestSupport.repositoryRoot()
        let productionPath = repository.appendingPathComponent(
            "apps/ios/Merian/\(Self.errorFormatterPath)"
        )
        let testPath = repository.appendingPathComponent(
            "apps/ios/MerianTests/Features/Explore/Shared/ExploreErrorFormatterTests.swift"
        )
        let retiredProductionPath = repository.appendingPathComponent(
            "apps/ios/Merian/Core/Utilities/ExploreErrorFormatter.swift"
        )
        let retiredAggregatePath = repository.appendingPathComponent(
            "apps/ios/MerianTests/Core/Utilities/MerianConfigTests.swift"
        )

        #expect(FileManager.default.fileExists(atPath: productionPath.path))
        #expect(FileManager.default.fileExists(atPath: testPath.path))
        #expect(!FileManager.default.fileExists(atPath: retiredProductionPath.path))
        #expect(!FileManager.default.fileExists(atPath: retiredAggregatePath.path))

        let focusedTests = try String(contentsOf: testPath, encoding: .utf8)
        let focusedTestDeclaration = "struct ExploreError"
            + "FormatterTests"
        let testOwners = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/MerianTests"
        ).compactMap { source in
            source.contents.contains(focusedTestDeclaration)
                ? source.relativePath
                : nil
        }

        #expect(testOwners == [Self.errorFormatterTestPath])
        #expect(focusedTests.contains(focusedTestDeclaration))
    }

    @Test func productionFilesStayBounded() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/Merian/Features/Explore/Shared"
        )

        #expect(!sources.isEmpty)
        for source in sources {
            #expect(
                DatabaseActorTestSupport.lineCount(of: source.contents) <= 600,
                "\(source.relativePath) exceeds the 600-line review ceiling"
            )
        }
    }

    private func imports(in source: String) -> [String] {
        source.split(separator: "\n")
            .map(String.init)
            .filter { $0.hasPrefix("import ") }
    }

    private static let errorFormatterPath =
        "Features/Explore/Shared/Models/ExploreErrorFormatter.swift"
    private static let errorFormatterTestPath =
        "Features/Explore/Shared/ExploreErrorFormatterTests.swift"
    private static let forbiddenErrorPresentationEffects = [
        "AppDIContainer",
        "MerianLog",
        "MerianNetworkClient",
        "ModelContext",
        "SupabaseManager",
        "Task {",
        "UIApplication",
        "URLSession",
        "UserDefaults"
    ]
}
