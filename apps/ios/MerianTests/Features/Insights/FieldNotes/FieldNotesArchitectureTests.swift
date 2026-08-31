import Foundation
import Testing

@testable import Merian

struct FieldNotesArchitectureTests {
    @Test func ownershipDirectoriesAndLineCeilingRemainPresent() throws {
        let root = try fieldNotesSourceRoot()
        for directory in [
            "Models",
            "Services",
            "ViewModels",
            "Views",
            "Components/Card",
            "Components/Editor"
        ] {
            var isDirectory: ObjCBool = false
            let path = root.appendingPathComponent(directory).path
            #expect(
                FileManager.default.fileExists(
                    atPath: path,
                    isDirectory: &isDirectory
                ),
                "Field Notes is missing its \(directory) owner"
            )
            #expect(isDirectory.boolValue)
        }

        for file in try swiftFiles(in: root) {
            let lineCount = try contents(of: file)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .count
            #expect(
                lineCount <= 600,
                "\(file.lastPathComponent) has \(lineCount) lines"
            )
        }
    }

    @Test func liveEffectsRemainServicesOnly() throws {
        let forbidden = [
            "AppDIContainer.shared",
            "HapticManager.shared",
            "FieldNotesRepository.",
            "speechManager.startDictation",
            "speechManager.stopDictation"
        ]

        for file in try swiftFiles(in: fieldNotesSourceRoot()) {
            guard !file.pathComponents.contains("Services") else { continue }
            let source = try contents(of: file)
            for token in forbidden {
                #expect(
                    !source.contains(token),
                    "\(file.lastPathComponent) resolves \(token)"
                )
            }
        }
    }

    @Test func viewsAndComponentsOwnNoNetworkClients() throws {
        let root = try fieldNotesSourceRoot()
        let forbidden = [
            "MerianNetworkClient",
            "URLSession",
            "SupabaseManager",
            ".client.from(",
            ".rpc("
        ]

        for directory in ["Views", "Components"] {
            for file in try swiftFiles(
                in: root.appendingPathComponent(directory)
            ) {
                let source = try contents(of: file)
                for token in forbidden {
                    #expect(
                        !source.contains(token),
                        "\(file.lastPathComponent) owns \(token)"
                    )
                }
            }
        }
    }

    @Test func modelsRemainPlatformNeutral() throws {
        let models = try fieldNotesSourceRoot()
            .appendingPathComponent("Models")
        for file in try swiftFiles(in: models) {
            let source = try contents(of: file)
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

    @Test func legacyAggregatesAndTestLocationsAreRemoved() throws {
        let root = try repositoryRoot()
        for relativePath in [
            "apps/ios/Merian/Features/Insights/FieldNotes/Components/FieldNotesCard.swift",
            "apps/ios/MerianTests/Features/Insights/FieldNotesEditPolicyTests.swift"
        ] {
            #expect(
                !FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(relativePath).path
                ),
                "Legacy Field Notes owner remains at \(relativePath)"
            )
        }
    }

    @Test func featureDeclaresNoUncheckedSendableConformance() throws {
        for file in try swiftFiles(in: fieldNotesSourceRoot()) {
            let source = try contents(of: file)
            #expect(
                !source.contains("@unchecked Sendable"),
                "\(file.lastPathComponent) bypasses sendability checking"
            )
        }
    }

    private func fieldNotesSourceRoot() throws -> URL {
        let root = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Features/Insights/FieldNotes"
        )
        #expect(FileManager.default.fileExists(atPath: root.path))
        return root
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

    private func swiftFiles(in root: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys)
            )
        else { return [] }

        return try enumerator.compactMap { element in
            guard let url = element as? URL,
                url.pathExtension == "swift",
                try url.resourceValues(forKeys: keys).isRegularFile == true
            else { return nil }
            return url
        }
    }

    private func contents(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }
}
