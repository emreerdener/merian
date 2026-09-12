import Foundation
import Testing

@Suite("Feature Flag Architecture")
struct FeatureFlagsArchitectureTests {
    @Test func appReleaseGatesHaveOneConfigurationOwner() throws {
        let sources = try swiftSources(
            below: "apps/ios/Merian"
        )
        let flagOwners = sources.compactMap { source in
            source.contents.contains("enum FeatureFlag: String")
                ? source.relativePath
                : nil
        }
        let resolverOwners = sources.compactMap { source in
            source.contents.contains("enum FeatureFlags {")
                ? source.relativePath
                : nil
        }

        #expect(flagOwners == [Self.featureFlagsPath])
        #expect(resolverOwners == [Self.featureFlagsPath])

        let source = try repositorySource(
            at: "apps/ios/Merian/\(Self.featureFlagsPath)"
        )
        #expect(imports(in: source) == ["import Foundation"])
        #expect(source.contains("\"Merian.DebugFeatureFlag.\""))
        for effectToken in Self.forbiddenConfigurationEffects {
            #expect(
                !source.contains(effectToken),
                "FeatureFlags resolves \(effectToken)"
            )
        }
        #expect(lineCount(of: source) <= 600)
    }

    @Test func fieldTripSharingHasOneFeatureOwner() throws {
        let sources = try swiftSources(
            below: "apps/ios/Merian"
        )
        let owners = sources.compactMap { source in
            source.contents.contains("enum FieldTripSharingAvailability")
                ? source.relativePath
                : nil
        }

        #expect(owners == [Self.fieldTripSharingPath])

        let source = try repositorySource(
            at: "apps/ios/Merian/\(Self.fieldTripSharingPath)"
        )
        #expect(imports(in: source).isEmpty)
        #expect(source.contains("static let isEnabled = false"))
        #expect(lineCount(of: source) <= 600)
    }

    @Test func behaviorTestsMirrorTheirProductionOwners() throws {
        let repository = try repositoryRoot()
        let expectedPaths = [
            "apps/ios/Merian/\(Self.featureFlagsPath)",
            "apps/ios/Merian/\(Self.fieldTripSharingPath)",
            "apps/ios/MerianTests/\(Self.featureFlagsTestPath)",
            "apps/ios/MerianTests/\(Self.fieldTripSharingTestPath)"
        ]

        for path in expectedPaths {
            #expect(FileManager.default.fileExists(
                atPath: repository.appendingPathComponent(path).path
            ))
        }

        for path in Self.retiredPaths {
            #expect(!FileManager.default.fileExists(
                atPath: repository.appendingPathComponent(path).path
            ))
        }

        let tests = try swiftSources(
            below: "apps/ios/MerianTests"
        )
        let featureFlagTestOwners = structOwners(
            named: "FeatureFlagsTests",
            in: tests
        )
        let sharingTestOwners = structOwners(
            named: "FieldTripSharingAvailabilityTests",
            in: tests
        )

        #expect(featureFlagTestOwners == [Self.featureFlagsTestPath])
        #expect(sharingTestOwners == [Self.fieldTripSharingTestPath])
    }

    @Test func configurationSwiftFilesStayBounded() throws {
        let sources = try swiftSources(
            below: "apps/ios/Merian/Configuration"
        )

        #expect(!sources.isEmpty)
        for source in sources {
            #expect(
                lineCount(of: source.contents) <= 600,
                "\(source.relativePath) exceeds the 600-line review ceiling"
            )
        }
    }

    private struct SwiftSource {
        let relativePath: String
        let contents: String
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        for _ in 0..<12 {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("project.yml").path
            ) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func repositorySource(at relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func swiftSources(below relativeRoot: String) throws -> [SwiftSource] {
        let sourceRoot = try repositoryRoot().appendingPathComponent(relativeRoot)
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: Array(keys)
        ) else { return [] }

        let files = try enumerator.compactMap { element -> URL? in
            guard let file = element as? URL,
                  file.pathExtension == "swift",
                  try file.resourceValues(forKeys: keys).isRegularFile == true
            else { return nil }
            return file
        }

        return try files.sorted { $0.path < $1.path }.map { file in
            SwiftSource(
                relativePath: String(
                    file.path.dropFirst(sourceRoot.path.count + 1)
                ),
                contents: try String(contentsOf: file, encoding: .utf8)
            )
        }
    }

    private func lineCount(of source: String) -> Int {
        source.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private func imports(in source: String) -> [String] {
        source.split(separator: "\n")
            .map(String.init)
            .filter { $0.hasPrefix("import ") }
    }

    private func structOwners(
        named name: String,
        in sources: [SwiftSource]
    ) -> [String] {
        let declaration = "struct \(name)"
        return sources.compactMap { source in
            let declaresType = source.contents.split(separator: "\n")
                .contains { line in
                    line.trimmingCharacters(in: .whitespaces)
                        .hasPrefix(declaration)
                }
            return declaresType ? source.relativePath : nil
        }
    }

    private static let featureFlagsPath = "Configuration/FeatureFlags.swift"
    private static let fieldTripSharingPath =
        "Features/Explore/FieldTrips/Models/FieldTripSharingAvailability.swift"
    private static let featureFlagsTestPath =
        "Configuration/FeatureFlagsTests.swift"
    private static let fieldTripSharingTestPath =
        "Features/Explore/FieldTrips/FieldTripSharingAvailabilityTests.swift"
    private static let retiredPaths = [
        "apps/ios/Merian/Core/Utilities/FieldTripsAvailability.swift",
        "apps/ios/MerianTests/Core/Utilities/FieldTripsAvailabilityTests.swift"
    ]
    private static let forbiddenConfigurationEffects = [
        "AppDIContainer",
        "MerianLog",
        "MerianNetworkClient",
        "ModelContext",
        "SupabaseManager",
        "Task {",
        "UIApplication",
        "URLSession"
    ]
}
