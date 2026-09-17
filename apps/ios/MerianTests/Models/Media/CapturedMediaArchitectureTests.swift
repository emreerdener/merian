import Foundation
import Testing

@Suite("Captured Media Architecture")
struct CapturedMediaArchitectureTests {
    @Test func capturedMediaDeclarationsHaveFocusedOwners() throws {
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

    @Test func valuesRemainEffectFreeAndCaptureOwnsSubmissionProjection() throws {
        let valueSources = try Self.valuePaths.map { path in
            (path, try source(at: path))
        }
        let submission = try source(at: Self.submissionProjectionPath)

        for (path, values) in valueSources {
            #expect(
                imports(in: values) == ["import Foundation"],
                "Unexpected imports in \(path)"
            )
            for token in Self.forbiddenValueEffects {
                #expect(
                    !values.contains(token),
                    "Captured media values must not resolve \(token) in \(path)"
                )
            }
        }

        #expect(
            submission.contains(
                "extension CapturedMediaSnapshot {\n" +
                    "    var submissionMediaProjection: CaptureSubmissionMediaProjection"
            )
        )
        #expect(valueSources.allSatisfy { !$0.1.contains("submissionMediaProjection") })
    }

    @Test func activeSchemaShapeRemainsV51AndAggregateStaysRetired() throws {
        let entry = try source(at: Self.entryPath)
        let schemaVersions = try source(
            at: "apps/ios/Merian/Models/SchemaVersions.swift"
        )
        let aliases = try source(
            at: "apps/ios/Merian/Models/Aliases.swift"
        )
        let root = try DatabaseActorTestSupport.repositoryRoot()

        #expect(entry.contains("@Model\npublic final class CapturedMediaEntry"))
        #expect(
            persistedPropertyLines(in: entry) == Self.persistedProperties,
            "CapturedMediaEntry stored shape changed without a V52 migration"
        )
        #expect(!entry.contains("@Relationship"))
        #expect(aliases.contains("typealias CurrentSchema = MerianSchemaV51"))
        #expect(!schemaVersions.contains("enum MerianSchemaV52"))
        for retiredPath in Self.retiredPaths {
            #expect(
                !FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(retiredPath).path
                ),
                "Retired captured-media path returned: \(retiredPath)"
            )
        }
    }

    @Test func productionAndTestOwnersStayWithinReviewGuard() throws {
        for path in Self.productionPaths + Self.testPaths {
            let contents = try source(at: path)
            #expect(
                DatabaseActorTestSupport.lineCount(of: contents) <= 600,
                "\(path) exceeds the 600-line review ceiling"
            )
        }
    }

    private func source(at relativePath: String) throws -> String {
        try DatabaseActorTestSupport.loadRepositorySource(at: relativePath)
    }

    private func imports(in source: String) -> [String] {
        source.split(separator: "\n")
            .map(String.init)
            .filter { $0.hasPrefix("import ") }
    }

    private func persistedPropertyLines(in source: String) -> [String] {
        source.split(separator: "\n")
            .compactMap { line -> String? in
                let line = String(line)
                guard line.hasPrefix("    "),
                      !line.hasPrefix("        ") else {
                    return nil
                }
                let declaration = line.trimmingCharacters(in: .whitespaces)
                let declaresProperty = declaration.hasPrefix("var ")
                    || declaration.hasPrefix("let ")
                    || declaration.contains(" var ")
                    || declaration.contains(" let ")
                guard declaresProperty, !declaration.contains("{") else {
                    return nil
                }
                return declaration
            }
    }

    private static let valuesPath =
        "apps/ios/Merian/Models/Media/CapturedMediaValues.swift"
    private static let observationContextPath =
        "apps/ios/Merian/Models/Media/ObservationContext.swift"
    private static let valuePaths = [valuesPath, observationContextPath]
    private static let entryPath =
        "apps/ios/Merian/Models/ActiveSchema/CapturedMediaEntry.swift"
    private static let submissionProjectionPath =
        "apps/ios/Merian/Features/Capture/Submission/Models/" +
        "CaptureSubmissionMediaProjection.swift"
    private static let retiredPaths = [
        "apps/ios/Merian/Models/ActiveSchema/SerializedMediaItem.swift",
        "apps/ios/Merian/Features/Capture/Shared/Models/ObservationContext.swift",
        "apps/ios/Merian/Core/Data/CapturedMediaPersistenceService.swift",
        "apps/ios/MerianTests/Models/ObservationContextTests.swift",
        "apps/ios/MerianTests/Models/SerializedMediaItemTests.swift",
        "apps/ios/MerianTests/Models/ActiveSchema/CapturedMediaEntryTests.swift",
        "apps/ios/MerianTests/Core/Data/Database/CapturedMediaPersistenceServiceTests.swift"
    ]

    private static let productionPaths = [
        valuesPath,
        observationContextPath,
        entryPath,
        "apps/ios/Merian/Core/Media/CapturedMediaResolution.swift",
        "apps/ios/Merian/Core/Data/CapturedMedia/CapturedMediaCloudHydration.swift",
        "apps/ios/Merian/Core/Data/CapturedMedia/CapturedMediaPersistenceService.swift",
        "apps/ios/Merian/Core/Data/CapturedMedia/CapturedMediaRecordPersistence.swift",
        submissionProjectionPath
    ]

    private static let testPaths = [
        "apps/ios/MerianTests/Models/Media/CapturedMediaArchitectureTests.swift",
        "apps/ios/MerianTests/Models/Media/CapturedMediaValuesTests.swift",
        "apps/ios/MerianTests/Core/Media/CapturedMediaResolutionTests.swift",
        "apps/ios/MerianTests/Core/Data/CapturedMedia/CapturedMediaCloudHydrationTests.swift",
        "apps/ios/MerianTests/Core/Data/CapturedMedia/CapturedMediaPersistenceServiceTests.swift",
        "apps/ios/MerianTests/Core/Data/CapturedMedia/CapturedMediaRecordPersistenceTests.swift"
    ]

    private static let declarationOwners: [(token: String, path: String)] = [
        ("enum MediaStorageLocation:", "Models/Media/CapturedMediaValues.swift"),
        ("struct ObservationContext:", "Models/Media/ObservationContext.swift"),
        ("struct StoredMediaReference:", "Models/Media/CapturedMediaValues.swift"),
        ("struct StoredVideoMediaReference:", "Models/Media/CapturedMediaValues.swift"),
        ("enum SerializedMediaItem:", "Models/Media/CapturedMediaValues.swift"),
        ("struct CapturedMediaSnapshot:", "Models/Media/CapturedMediaValues.swift"),
        ("enum CapturedMediaKind:", "Models/Media/CapturedMediaValues.swift"),
        ("struct CapturedMediaSummary:", "Models/Media/CapturedMediaValues.swift"),
        ("enum MediaJSONParser {", "Models/Media/CapturedMediaValues.swift"),
        (
            "enum CloudMediaReplacementPolicy {",
            "Core/Data/CapturedMedia/CapturedMediaCloudHydration.swift"
        ),
        (
            "struct CapturedMediaPersistenceService: Sendable",
            "Core/Data/CapturedMedia/CapturedMediaPersistenceService.swift"
        ),
        (
            "public final class CapturedMediaEntry",
            "Models/ActiveSchema/CapturedMediaEntry.swift"
        )
    ]

    private static let persistedProperties = [
        "@Attribute(.unique) public var id: String",
        "public var orderIndex: Int",
        "public var kindRaw: String",
        "public var storageRaw: String",
        "public var mediaPath: String",
        "public var observationContextJSON: String"
    ]

    private static let forbiddenValueEffects = [
        "ActiveScanMedia",
        "AppDIContainer",
        "CaptureSubmissionMediaProjection",
        "CloudMediaReplacementPolicy",
        "FileManager",
        "MerianNetworkClient",
        "ModelContext",
        "SecureTransportPolicy",
        "SupabaseManager",
        "SwiftData",
        "Task {",
        "URLSession"
    ]
}
