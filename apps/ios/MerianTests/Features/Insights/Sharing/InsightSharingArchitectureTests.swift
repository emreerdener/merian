import Foundation
import Testing

@testable import Merian

struct InsightSharingArchitectureTests {
    @Test func ownershipDirectoriesAndLineCeilingRemainPresent() throws {
        let root = try sharingSourceRoot()
        for directory in [
            "Models",
            "Services",
            "ViewModels",
            "Views",
            "Components"
        ] {
            var isDirectory: ObjCBool = false
            let path = root.appendingPathComponent(directory).path
            #expect(
                FileManager.default.fileExists(
                    atPath: path,
                    isDirectory: &isDirectory
                ),
                "Insight Sharing is missing its \(directory) owner"
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

    @Test func liveResolutionIsServicesOnly() throws {
        let root = try sharingSourceRoot()
        let forbidden = [
            "MerianNetworkClient.shared",
            "AppDIContainer.shared",
            "HapticManager.shared",
            "ExploreShareStateStore.",
            "SpeciesPreferredNameRepository."
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

    @Test func viewsAndComponentsOwnNoNetworkClients() throws {
        let root = try sharingSourceRoot()
        let forbidden = [
            "MerianNetworkClient",
            "URLSession",
            "SupabaseManager",
            ".client.from("
        ]

        for directory in ["Views", "Components"] {
            for file in try swiftFiles(
                in: root.appendingPathComponent(directory)
            ) {
                let source = try String(contentsOf: file, encoding: .utf8)
                for token in forbidden {
                    #expect(
                        !source.contains(token),
                        "\(file.lastPathComponent) owns \(token)"
                    )
                }
            }
        }
    }

    @Test func modelsRemainPlatformNeutralAndAggregateIsRemoved() throws {
        let root = try sharingSourceRoot()
        for file in try swiftFiles(
            in: root.appendingPathComponent("Models")
        ) {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!source.contains("import SwiftUI"))
            #expect(!source.contains("import UIKit"))
            #expect(!source.contains("MerianNetworkClient"))
        }

        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "ViewModels/InsightSheetViewModel+ExploreSharing.swift"
                ).path
            )
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "CommunityIdentification"
                ).path
            )
        )
    }

    private func sharingSourceRoot() throws -> URL {
        let root = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Features/Insights/Sharing"
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
