import Foundation
import Testing

@Suite("Species Dictionary Catalog Architecture")
struct SpeciesDictionaryCatalogArchitectureTests {
    @Test func ownershipDirectoriesAndLineCeilingRemainPresent() throws {
        let root = try catalogSourceRoot()
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
        for directory in ["Catalog", "Overview", "Regions", "Shared"] {
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

    @Test func viewsAndComponentsOwnNoDirectNetworking() throws {
        let root = try catalogSourceRoot()
        let forbidden = [
            "MerianNetworkClient",
            "LocalImageLoader",
            "CLGeocoder",
            "MKMapSnapshotter",
            "AsyncImage(",
            "URLSession",
            ".client.from(",
            ".rpc("
        ]

        for directory in ["Views", "Components"] {
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

    @Test func liveResolutionRemainsServicesOwned() throws {
        let root = try catalogSourceRoot()
        let forbidden = [
            "MerianNetworkClient.shared",
            "LocalImageLoader.shared",
            "CLGeocoder()",
            "MKMapSnapshotter("
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
        let root = try catalogSourceRoot()
        for file in try swiftFiles(
            in: root.appendingPathComponent("Models")
        ) {
            let source = try String(contentsOf: file, encoding: .utf8)
            for forbiddenImport in [
                "import SwiftUI",
                "import UIKit",
                "import MapKit",
                "import CoreLocation"
            ] {
                #expect(!source.contains(forbiddenImport))
            }
            #expect(!source.contains("MerianNetworkClient"))
            #expect(!source.contains("struct SpeciesDictionaryCatalogItem"))
            #expect(!source.contains("struct SpeciesDictionaryOverview"))
        }

        let apiModels = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Core/Network/SpeciesDictionaryAPIModels.swift"
        )
        let source = try String(contentsOf: apiModels, encoding: .utf8)
        #expect(source.contains("struct SpeciesDictionaryCatalogItem"))
        #expect(source.contains("struct SpeciesDictionaryOverview"))
    }

    @Test func rootViewsStaySeparatedAndRouteRemainsModelOwned() throws {
        let root = try catalogSourceRoot()
        let views = root.appendingPathComponent("Views")
        for file in [
            "SpeciesDictionaryCatalogView.swift",
            "SpeciesDictionaryOverviewView.swift",
            "SpeciesDictionaryRegionsView.swift"
        ] {
            #expect(
                FileManager.default.fileExists(
                    atPath: views.appendingPathComponent(file).path
                )
            )
        }

        let catalogView = try String(
            contentsOf: views.appendingPathComponent(
                "SpeciesDictionaryCatalogView.swift"
            ),
            encoding: .utf8
        )
        #expect(!catalogView.contains("struct SpeciesDictionaryOverviewView"))
        #expect(!catalogView.contains("struct SpeciesDictionaryRegionsView"))

        let route = root.appendingPathComponent(
            "Models/SpeciesDictionaryCatalogRoute.swift"
        )
        #expect(FileManager.default.fileExists(atPath: route.path))
    }

    @Test func catalogSelectionIsFencedBeforeTheSearchDebounce() throws {
        let catalogView = try String(
            contentsOf: catalogSourceRoot().appendingPathComponent(
                "Views/SpeciesDictionaryCatalogView.swift"
            ),
            encoding: .utf8
        )
        let taskRange = try #require(
            catalogView.range(of: ".task(id: catalogSelection)")
        )
        let searchRange = taskRange.upperBound..<catalogView.endIndex
        let selectionRange = try #require(
            catalogView.range(
                of: "viewModel.updateSelection(selection)",
                range: searchRange
            )
        )
        let debounceRange = try #require(
            catalogView.range(
                of: "Task.sleep(nanoseconds: 300_000_000)",
                range: searchRange
            )
        )

        #expect(selectionRange.lowerBound < debounceRange.lowerBound)
    }

    private func catalogSourceRoot() throws -> URL {
        let root = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Features/SpeciesDictionary/Catalog"
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
