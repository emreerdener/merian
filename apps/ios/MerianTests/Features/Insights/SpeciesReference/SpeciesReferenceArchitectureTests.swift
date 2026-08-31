import Foundation
import Testing

@testable import Merian

struct SpeciesReferenceArchitectureTests {
    @Test func ownershipDirectoriesAndLineCeilingRemainPresent() throws {
        let root = try speciesReferenceSourceRoot()
        for directory in [
            "Models",
            "Services",
            "ViewModels",
            "Views",
            "Components/Charts",
            "Components/Habitat",
            "Components/Lookalikes",
            "Components/Maps",
            "Components/Taxonomy"
        ] {
            var isDirectory: ObjCBool = false
            let path = root.appendingPathComponent(directory).path
            #expect(
                FileManager.default.fileExists(
                    atPath: path,
                    isDirectory: &isDirectory
                ),
                "Species Reference is missing its \(directory) owner"
            )
            #expect(isDirectory.boolValue)
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

    @Test func liveEffectsAreServicesOnly() throws {
        let root = try speciesReferenceSourceRoot()
        let forbidden = [
            "AppDIContainer.shared",
            "HapticManager.shared",
            "LocalImageLoader.shared",
            "MerianNetworkClient.shared",
            "URLSession",
            "fetchAndApplyEnrichment("
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

    @Test func modelsRemainPlatformNeutral() throws {
        let models = try speciesReferenceSourceRoot()
            .appendingPathComponent("Models")
        for file in try swiftFiles(in: models) {
            let source = try String(contentsOf: file, encoding: .utf8)
            for forbiddenImport in [
                "import SwiftData",
                "import SwiftUI",
                "import UIKit"
            ] {
                #expect(
                    !source.contains(forbiddenImport),
                    "\(file.lastPathComponent) imports a UI/storage framework"
                )
            }
        }
    }

    @Test func featureDeclaresNoUncheckedSendableConformance() throws {
        let root = try speciesReferenceSourceRoot()
        for file in try swiftFiles(in: root) {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(
                !source.contains("@unchecked Sendable"),
                "\(file.lastPathComponent) bypasses sendability checking"
            )
        }
    }

    @Test func legacyAggregateOwnersAreRemoved() throws {
        let root = try speciesReferenceSourceRoot()
        for legacyPath in [
            "Cards/GBIFHeatmapMapView.swift",
            "Cards/HabitatAndDistributionCard.swift",
            "Cards/SimilarSpeciesGallery.swift",
            "Cards/SpeciesObservationChartsCard.swift",
            "Cards/TaxonomyCard.swift",
            "Utilities/SimilarSpeciesImageFetcher.swift",
            "Components/Maps/SpeciesReferencePinchPanOverlay.swift"
        ] {
            #expect(
                !FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(legacyPath).path
                ),
                "Legacy Species Reference owner remains at \(legacyPath)"
            )
        }
    }

    @Test func mapGestureBridgeRemainsFilePrivate() throws {
        let mapSource = try String(
            contentsOf: speciesReferenceSourceRoot()
                .appendingPathComponent(
                    "Components/Maps/GBIFHeatmapMapView.swift"
                ),
            encoding: .utf8
        )

        #expect(
            mapSource.contains("private struct GBIFHeatmapPinchPanOverlay")
        )
    }

    private func speciesReferenceSourceRoot() throws -> URL {
        let root = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Features/Insights/SpeciesReference"
        )
        #expect(FileManager.default.fileExists(atPath: root.path))
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

    private func swiftFiles(in root: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys)
        ) else { return [] }

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
