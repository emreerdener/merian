import Foundation
import Testing

@Suite("Image Loading Architecture")
struct ImageLoadingArchitectureTests {
    @Test func declarationsHaveFocusedOwners() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: Self.imageDirectory
        )

        for (declaration, expectedPath) in Self.declarationOwners {
            let owners = sources.compactMap { source in
                source.contents.contains(declaration)
                    ? source.relativePath
                    : nil
            }
            #expect(
                owners == [expectedPath],
                "\(declaration) changed ownership"
            )
        }

        let loader = try source("LocalImageLoader.swift")
        for relocatedDeclaration in Self.relocatedDeclarations {
            #expect(!loader.contains(relocatedDeclaration))
        }
    }

    @Test func imageDataOwnersStayBoundedAndDependencyFocused() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: Self.imageDirectory
        )
        for source in sources {
            #expect(
                DatabaseActorTestSupport.lineCount(of: source.contents) <= 600,
                "\(source.relativePath) exceeds the 600-line review ceiling"
            )
        }

        for (path, expectedImports) in Self.extractedOwnerImports {
            let contents = try source(path)
            #expect(
                imports(in: contents) == expectedImports,
                "\(path) has an unexpected framework dependency"
            )
        }

        let externalPolicy = try source(
            "Policies/ExternalReferenceImagePolicy.swift"
        )
        let retryPolicy = try source("Policies/RemoteImageRetryPolicy.swift")
        let permitPool = try source("Concurrency/AsyncPermitPool.swift")
        let recovery = try source(
            "Recovery/LocalScanMediaRecoveryResolver.swift"
        )
        let loader = try source("LocalImageLoader.swift")

        for contents in [
            externalPolicy,
            retryPolicy,
            permitPool,
            recovery
        ] {
            #expect(!contents.contains("MerianNetworkClient"))
            #expect(!contents.contains("AppDIContainer.shared"))
            #expect(!contents.contains("URLSession"))
            #expect(!contents.contains("Task.detached"))
        }
        #expect(!loader.contains("MerianNetworkClient.shared"))
        #expect(!loader.contains("AppDIContainer.shared"))
        #expect(!loader.contains("import SQLite3"))
    }

    @Test func cloudRepairContainsLiveEffectsBehindDependencies() throws {
        let repair = try source(
            "Services/CloudScanImageRepairActor.swift"
        )
        let operationalStart = try #require(repair.range(
            of: "private var pending:"
        ))
        let operationalBody = repair[operationalStart.lowerBound...]

        #expect(repair.contains("struct Dependencies: Sendable"))
        #expect(repair.contains("static let live = Dependencies("))
        #expect(repair.contains(
            "private let dependencies: Dependencies"
        ))
        #expect(repair.contains(
            "private var processingTask: Task<Void, Never>?"
        ))
        #expect(repair.contains(
            "private var queuedOrInFlightSourceURLs: Set<String>"
        ))
        #expect(operationalBody.contains(
            ".canonicalRecoverySourceURL(for: sourceURL)"
        ))
        #expect(!operationalBody.contains("MerianNetworkClient.shared"))
        #expect(!operationalBody.contains("AppDIContainer.shared"))
        #expect(!operationalBody.contains("ProcessInfo.processInfo"))
        #expect(!operationalBody.contains("FileManager.default"))
        let bodyWithoutInjectedUUID = operationalBody.replacingOccurrences(
            of: "makeUUID()",
            with: ""
        )
        #expect(!bodyWithoutInjectedUUID.contains("UUID()"))
    }

    @Test func loaderTestsMirrorTheImageOwner() throws {
        let repository = try DatabaseActorTestSupport.repositoryRoot()
        let oldPath = repository.appendingPathComponent(
            "apps/ios/MerianTests/Core/Data/LocalImageLoaderTests.swift"
        )
        let newPath = repository.appendingPathComponent(
            "apps/ios/MerianTests/Core/Data/Images/LocalImageLoaderTests.swift"
        )
        let repairPath = repository.appendingPathComponent(
            "apps/ios/MerianTests/Core/Data/Images/CloudScanImageRepairActorTests.swift"
        )

        #expect(!FileManager.default.fileExists(atPath: oldPath.path))
        #expect(FileManager.default.fileExists(atPath: newPath.path))
        #expect(FileManager.default.fileExists(atPath: repairPath.path))

        let loaderTests = try String(
            contentsOf: newPath,
            encoding: .utf8
        )
        #expect(loaderTests.contains("struct LocalImageLoaderTests"))
        #expect(loaderTests.contains(
            "testLocalImageLoader_ConcurrentDeduplication"
        ))
        #expect(loaderTests.contains(
            "#expect(await probe.requestCount == 1)"
        ))
        #expect(!loaderTests.contains("example.com/dummy"))
    }

    private static let imageDirectory =
        "apps/ios/Merian/Core/Data/Images"

    private static let declarationOwners = [
        "enum ExternalReferenceImagePolicy":
            "Policies/ExternalReferenceImagePolicy.swift",
        "actor AsyncPermitPool":
            "Concurrency/AsyncPermitPool.swift",
        "enum RemoteImageRetryPolicy":
            "Policies/RemoteImageRetryPolicy.swift",
        "enum LocalScanMediaRecoveryResolver":
            "Recovery/LocalScanMediaRecoveryResolver.swift",
        "final class LocalScanMediaRecoveryRegistry":
            "Recovery/LocalScanMediaRecoveryRegistry.swift",
        "enum LegacyScanMediaRecoveryStoreLocator":
            "Recovery/LegacyScanMediaRecoveryIndex.swift",
        "final class LegacyScanMediaRecoveryIndex":
            "Recovery/LegacyScanMediaRecoveryIndex.swift",
        "actor CloudScanImageRepairActor":
            "Services/CloudScanImageRepairActor.swift",
        "actor LocalImageLoader":
            "LocalImageLoader.swift"
    ]

    private static let relocatedDeclarations = [
        "enum ExternalReferenceImagePolicy",
        "actor AsyncPermitPool",
        "enum RemoteImageRetryPolicy",
        "enum LocalScanMediaRecoveryResolver",
        "final class LocalScanMediaRecoveryRegistry",
        "enum LegacyScanMediaRecoveryStoreLocator",
        "final class LegacyScanMediaRecoveryIndex",
        "actor CloudScanImageRepairActor"
    ]

    private static let extractedOwnerImports = [
        "LocalImageLoader.swift": [
            "import Foundation",
            "import UIKit"
        ],
        "Concurrency/AsyncPermitPool.swift": [
            "import Foundation"
        ],
        "Policies/ExternalReferenceImagePolicy.swift": [
            "import Foundation"
        ],
        "Policies/RemoteImageRetryPolicy.swift": [
            "import Foundation"
        ],
        "Recovery/LocalScanMediaRecoveryResolver.swift": [
            "import Foundation"
        ],
        "Recovery/LocalScanMediaRecoveryRegistry.swift": [
            "import Foundation"
        ],
        "Recovery/LegacyScanMediaRecoveryIndex.swift": [
            "import Foundation",
            "import SQLite3"
        ],
        "Services/CloudScanImageRepairActor.swift": [
            "import Foundation"
        ]
    ]

    private func source(_ path: String) throws -> String {
        try DatabaseActorTestSupport.loadRepositorySource(
            at: "\(Self.imageDirectory)/\(path)"
        )
    }

    private func imports(in source: String) -> [String] {
        source.split(separator: "\n")
            .map(String.init)
            .filter { $0.hasPrefix("import ") }
    }
}
