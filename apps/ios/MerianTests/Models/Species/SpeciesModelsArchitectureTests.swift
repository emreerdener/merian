import Foundation
import Testing

@Suite("Species Models Architecture")
struct SpeciesModelsArchitectureTests {
    @Test func speciesValuesHaveFocusedOwners() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/Merian/Models/Species"
        )

        #expect(sources.map(\.relativePath) == Self.speciesSourcePaths)
        for source in sources {
            #expect(
                DatabaseActorTestSupport.lineCount(of: source.contents) <= 600,
                "\(source.relativePath) exceeds the 600-line review ceiling"
            )
            #expect(imports(in: source.contents) == ["import Foundation"])
            for token in Self.forbiddenSpeciesEffects {
                #expect(
                    !source.contents.contains(token),
                    "\(source.relativePath) must not resolve \(token)"
                )
            }
        }
    }

    @Test func declarationsRemainSingleOwner() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/Merian"
        )

        for expectation in Self.declarationOwners {
            let owners = sources.compactMap { source in
                source.contents.contains(expectation.token)
                    ? source.relativePath
                    : nil
            }
            #expect(
                owners == [expectation.path],
                "\(expectation.token) owners: \(owners)"
            )
        }
    }

    @Test func aiOwnsCaptureTelemetryAndEdgeMapping() throws {
        let capture = try source(at: Self.captureTelemetryPath)
        let edgeMapping = try source(at: Self.edgeMappingPath)

        #expect(imports(in: capture) == ["import Foundation"])
        #expect(capture.contains("struct CaptureTelemetry: Sendable"))
        #expect(capture.contains("init(from inferenceEngine: InferenceEngine)"))
        #expect(capture.contains("from context: EnvironmentContext"))

        #expect(imports(in: edgeMapping) == ["import Foundation"])
        #expect(edgeMapping.contains("fromEdgeResponse edgeResponse: EdgeResponse"))
        #expect(
            edgeMapping.contains(
                "SpeciesIdentificationResolutionPolicy.isResolved"
            )
        )

        for source in [capture, edgeMapping] {
            #expect(DatabaseActorTestSupport.lineCount(of: source) <= 600)
            for token in Self.forbiddenAIEffects {
                #expect(!source.contains(token), "Core AI model resolves \(token)")
            }
        }

        let speciesSources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/Merian/Models/Species"
        )
        for source in speciesSources {
            #expect(!source.contents.contains("EdgeResponse"))
            #expect(!source.contents.contains("CaptureTelemetry"))
            #expect(!source.contents.contains("EnvironmentContext"))
            #expect(!source.contents.contains("InferenceEngine"))
        }
    }

    @Test func focusedTestsMirrorOwnershipAndRetireAggregates() throws {
        let root = try DatabaseActorTestSupport.repositoryRoot()
        for path in Self.requiredPaths {
            #expect(
                FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(path).path
                ),
                "Missing focused species path: \(path)"
            )
        }
        for path in Self.retiredPaths {
            #expect(
                !FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(path).path
                ),
                "Retired aggregate returned: \(path)"
            )
        }

        let tests = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/MerianTests/Models/Species"
        )
        #expect(tests.map(\.relativePath) == Self.speciesTestPaths)
        for test in tests {
            #expect(
                DatabaseActorTestSupport.lineCount(of: test.contents) <= 600,
                "\(test.relativePath) exceeds the 600-line review ceiling"
            )
            if test.relativePath != "SpeciesModelsArchitectureTests.swift" {
                #expect(!test.contents.contains("EdgeResponse"))
                #expect(!test.contents.contains("fromEdgeResponse"))
            }
        }

        let aiModelTests = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/MerianTests/Core/AI/Models"
        )
        #expect(aiModelTests.map(\.relativePath) == Self.aiModelTestPaths)
        for test in aiModelTests {
            #expect(
                DatabaseActorTestSupport.lineCount(of: test.contents) <= 600,
                "\(test.relativePath) exceeds the 600-line review ceiling"
            )
        }

        let edgeTests = try source(at: Self.edgeMappingTestPath)
        let captureTests = try source(at: Self.captureTelemetryTestPath)
        #expect(edgeTests.contains("struct SpeciesDataEdgeResponseTests"))
        #expect(edgeTests.contains("fromEdgeResponse: wrapper.data"))
        #expect(!captureTests.contains("nonDefaultZoomFactor"))
    }

    private func source(at relativePath: String) throws -> String {
        try DatabaseActorTestSupport.loadRepositorySource(at: relativePath)
    }

    private func imports(in source: String) -> [String] {
        source.split(separator: "\n")
            .map(String.init)
            .filter { $0.hasPrefix("import ") }
    }

    private static let speciesSourcePaths = [
        "SimilarSpecies.swift",
        "SpeciesData+Presentation.swift",
        "SpeciesData.swift",
        "SpeciesObservationModels.swift"
    ]

    private static let speciesTestPaths = [
        "SimilarSpeciesTests.swift",
        "SpeciesDataTests.swift",
        "SpeciesModelsArchitectureTests.swift",
        "SpeciesObservationModelsTests.swift"
    ]

    private static let aiModelTestPaths = [
        "CaptureTelemetryTests.swift",
        "SpeciesDataEdgeResponseTests.swift"
    ]

    private static let captureTelemetryPath =
        "apps/ios/Merian/Core/AI/Models/CaptureTelemetry.swift"
    private static let edgeMappingPath =
        "apps/ios/Merian/Core/AI/Models/SpeciesData+EdgeResponse.swift"
    private static let edgeMappingTestPath =
        "apps/ios/MerianTests/Core/AI/Models/SpeciesDataEdgeResponseTests.swift"
    private static let captureTelemetryTestPath =
        "apps/ios/MerianTests/Core/AI/Models/CaptureTelemetryTests.swift"

    private static let declarationOwners: [(token: String, path: String)] = [
        ("struct CaptureTelemetry: Sendable", "Core/AI/Models/CaptureTelemetry.swift"),
        ("struct SpeciesData: Sendable", "Models/Species/SpeciesData.swift"),
        (
            "enum SpeciesDataPresentationRole: Sendable, Equatable",
            "Models/Species/SpeciesData.swift"
        ),
        (
            "enum ReferenceImageVisibilityPolicy",
            "Models/Species/SpeciesData+Presentation.swift"
        ),
        (
            "enum HumanSubjectIdentityPolicy",
            "Models/Species/SpeciesData+Presentation.swift"
        ),
        (
            "enum SpeciesIdentificationResolutionPolicy",
            "Models/Species/SpeciesData+Presentation.swift"
        ),
        (
            "struct PetIdentification: Codable, Equatable, Hashable, Sendable",
            "Models/Species/SpeciesObservationModels.swift"
        ),
        ("struct TaxonomyData: Sendable", "Models/Species/SpeciesObservationModels.swift"),
        ("struct InsightData: Sendable", "Models/Species/SpeciesObservationModels.swift"),
        (
            "struct IdentificationCandidate: Codable, Sendable",
            "Models/Species/SpeciesObservationModels.swift"
        ),
        ("struct SimilarSpeciesEntry: Codable, Sendable", "Models/Species/SimilarSpecies.swift"),
        ("struct SimilarSpecies: Sendable", "Models/Species/SimilarSpecies.swift"),
        (
            "fromEdgeResponse edgeResponse: EdgeResponse",
            "Core/AI/Models/SpeciesData+EdgeResponse.swift"
        )
    ]

    private static let forbiddenSpeciesEffects = [
        "AppDIContainer",
        "FileManager",
        "InferenceEngine",
        "MerianNetworkClient",
        "ModelContext",
        "SupabaseManager",
        "Task {",
        "URLSession"
    ]

    private static let forbiddenAIEffects = [
        "AppDIContainer",
        "FileManager",
        "MerianNetworkClient",
        "ModelContext",
        "SupabaseManager",
        "Task {",
        "URLSession"
    ]

    private static let requiredPaths = speciesSourcePaths.map {
        "apps/ios/Merian/Models/Species/\($0)"
    } + speciesTestPaths.map {
        "apps/ios/MerianTests/Models/Species/\($0)"
    } + [
        captureTelemetryPath,
        edgeMappingPath,
        captureTelemetryTestPath,
        edgeMappingTestPath
    ]

    private static let retiredPaths = [
        "apps/ios/Merian/Models/SpeciesData.swift",
        "apps/ios/MerianTests/CaptureTelemetryTests.swift",
        "apps/ios/MerianTests/Models/SpeciesDataTests.swift"
    ]
}
