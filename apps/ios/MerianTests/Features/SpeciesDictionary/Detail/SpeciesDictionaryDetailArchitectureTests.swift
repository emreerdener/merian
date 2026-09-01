import Foundation
import Testing

@Suite("Species Dictionary Detail Architecture")
struct SpeciesDictionaryDetailArchitectureTests {
    @Test func ownershipDirectoriesAndLineCeilingRemainPresent() throws {
        let root = try detailSourceRoot()
        for directory in [
            "Models",
            "Services",
            "ViewModels",
            "Views",
            "Components"
        ] {
            try #require(isDirectory(root.appendingPathComponent(directory)))
        }

        let components = root.appendingPathComponent("Components")
        for directory in [
            "Community",
            "Content",
            "Gallery",
            "Loading",
            "Shared"
        ] {
            try #require(
                isDirectory(components.appendingPathComponent(directory))
            )
        }

        for file in try swiftFiles(in: root) {
            let lineCount = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .count
            #expect(
                lineCount <= 600,
                "\(file.lastPathComponent) has \(lineCount) lines"
            )
        }
    }

    @Test func viewsComponentsAndViewModelsOwnNoDirectNetworking() throws {
        let root = try detailSourceRoot()
        let forbidden = [
            "MerianNetworkClient",
            "URLSession",
            ".client.from(",
            ".rpc("
        ]

        for directory in ["Views", "Components", "ViewModels"] {
            for file in try swiftFiles(
                in: root.appendingPathComponent(directory)
            ) {
                let source = try String(contentsOf: file, encoding: .utf8)
                for token in forbidden {
                    #expect(
                        !source.contains(token),
                        "\(file.lastPathComponent) directly owns \(token)"
                    )
                }
            }
        }
    }

    @Test func liveResolutionAndTelemetryRemainServicesOwned() throws {
        let root = try detailSourceRoot()
        let forbidden = [
            "MerianNetworkClient.shared",
            "AppDIContainer.shared",
            "RevenueCatManager.shared",
            "HapticManager.shared",
            "AppTelemetry.",
            "InsightChatViewModel(source:"
        ]

        for file in try swiftFiles(in: root) {
            guard !file.pathComponents.contains("Services") else { continue }
            let source = try String(contentsOf: file, encoding: .utf8)
            for token in forbidden {
                #expect(
                    !source.contains(token),
                    "\(file.lastPathComponent) resolves \(token)"
                )
            }
        }
    }

    @Test func modelsRemainPlatformNeutralAndWireDTOsRemainCoreOwned() throws {
        let root = try detailSourceRoot()
        for file in try swiftFiles(
            in: root.appendingPathComponent("Models")
        ) {
            let source = try String(contentsOf: file, encoding: .utf8)
            for forbiddenImport in [
                "import SwiftUI",
                "import UIKit",
                "import Observation"
            ] {
                #expect(!source.contains(forbiddenImport))
            }
            #expect(!source.contains("MerianNetworkClient"))
            #expect(!source.contains("struct SpeciesDictionaryEntry"))
            #expect(!source.contains("struct SpeciesDictionaryResponse"))
        }

        let apiModels = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Core/Network/SpeciesDictionaryAPIModels.swift"
        )
        let source = try String(contentsOf: apiModels, encoding: .utf8)
        #expect(source.contains("struct SpeciesDictionaryEntry"))
        #expect(source.contains("struct SpeciesDictionaryResponse"))
        for presentationToken in [
            "struct SpeciesDictionaryRoute",
            "enum SpeciesDictionaryEntryPoint",
            "var effectiveContentQuality",
            "var taxonomyData",
            "var similarSpeciesData",
            "var fullscreenAttributionLabel"
        ] {
            #expect(!source.contains(presentationToken))
        }
    }

    @Test func rootAndContentViewsStaySeparated() throws {
        let views = try detailSourceRoot().appendingPathComponent("Views")
        let rootView = views.appendingPathComponent(
            "SpeciesDictionaryPageView.swift"
        )
        let contentView = views.appendingPathComponent(
            "SpeciesDictionaryPageContentView.swift"
        )

        #expect(FileManager.default.fileExists(atPath: rootView.path))
        #expect(FileManager.default.fileExists(atPath: contentView.path))

        let rootSource = try String(
            contentsOf: rootView,
            encoding: .utf8
        )
        let contentSource = try String(
            contentsOf: contentView,
            encoding: .utf8
        )
        #expect(!rootSource.contains("struct SpeciesDictionaryPresentation"))
        #expect(!rootSource.contains("struct SpeciesDictionaryPageContentView"))
        #expect(!contentSource.contains("struct SpeciesDictionaryPageView:"))
        #expect(!contentSource.contains("struct SpeciesDictionaryDetailLoadingSkeleton"))
    }

    @Test func retiredAggregateFilesStayAbsent() throws {
        let components = try detailSourceRoot().appendingPathComponent(
            "Components"
        )

        for file in [
            "SpeciesCommunitySightings.swift",
            "SpeciesDictionaryCards.swift",
            "SpeciesDictionaryReferenceGallery.swift"
        ] {
            #expect(
                !FileManager.default.fileExists(
                    atPath: components.appendingPathComponent(file).path
                ),
                "Retired aggregate \(file) must not be restored"
            )
        }
    }

    private func detailSourceRoot() throws -> URL {
        let root = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Features/SpeciesDictionary/Detail"
        )
        try #require(isDirectory(root))
        return root
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()

        for _ in 0..<10 {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("project.yml").path
            ) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }

        throw CocoaError(.fileNoSuchFile)
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }

    private func swiftFiles(in root: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys)
        ) else {
            return []
        }

        return try enumerator.compactMap { element in
            guard let url = element as? URL,
                  url.pathExtension == "swift",
                  try url.resourceValues(forKeys: keys).isRegularFile == true
            else {
                return nil
            }
            return url
        }
    }
}
