import Foundation
import Testing

@Suite("Core Preferences Architecture")
struct PreferencesArchitectureTests {
    @Test func extractedOwnerInventoryIsExact() throws {
        let root = try preferencesRoot()
        let actualPaths = try Set(swiftFiles(below: root).map {
            $0.path.replacingOccurrences(of: root.path + "/", with: "")
        })

        #expect(actualPaths == Self.expectedProductionPaths)
        #expect(Set(Self.expectedImportsByPath.keys) == Self.expectedProductionPaths)
    }

    @Test func extractedDeclarationsHaveOneOwner() throws {
        let repositoryRoot = try repositoryRoot()
        let coreSources = try swiftFiles(
            below: repositoryRoot.appendingPathComponent(
                "apps/ios/Merian/Core"
            )
        )

        for (declaration, expectedPath) in Self.expectedDeclarationOwners {
            let owners = try coreSources.compactMap { file -> String? in
                let source = try contents(of: file)
                guard source.contains(declaration) else { return nil }
                return file.path.replacingOccurrences(
                    of: repositoryRoot.path + "/",
                    with: ""
                )
            }
            #expect(owners == [expectedPath])
        }

        let aggregate = try contents(
            of: repositoryRoot.appendingPathComponent(
                "apps/ios/Merian/Core/Utilities/UserDefaultsKeys.swift"
            )
        )
        for declaration in Self.expectedDeclarationOwners.keys {
            #expect(!aggregate.contains(declaration))
        }
        for retiredImport in [
            "import Combine",
            "import Observation",
            "import UIKit"
        ] {
            #expect(!aggregate.contains(retiredImport))
        }
    }

    @Test func preferenceOwnersRemainNarrowAndBelowTheReviewCeiling() throws {
        let root = try preferencesRoot()
        for file in try swiftFiles(below: root) {
            let source = try contents(of: file)
            let relativePath = file.path.replacingOccurrences(
                of: root.path + "/",
                with: ""
            )
            let lineCount = source.split(
                separator: "\n",
                omittingEmptySubsequences: false
            ).count
            #expect(
                lineCount <= 600,
                "\(file.lastPathComponent) has \(lineCount) lines"
            )
            let imports = Set(
                source.split(separator: "\n")
                    .map(String.init)
                    .filter { $0.hasPrefix("import ") }
            )
            #expect(
                imports == Self.expectedImportsByPath[relativePath, default: []],
                "\(relativePath) has an unexpected framework dependency"
            )
            for forbiddenToken in [
                "AppDIContainer",
                "MerianNetworkClient",
                "SupabaseManager",
                "URLSession",
                ".from(\"",
                ".rpc("
            ] {
                #expect(
                    !source.contains(forbiddenToken),
                    "\(file.lastPathComponent) resolves \(forbiddenToken)"
                )
            }
        }
    }

    private static let expectedProductionPaths: Set<String> = [
        "AccountScopedPreferences.swift",
        "AccountScopedRuntimeState.swift",
        "AppSettings.swift",
        "Stores/ExploreShareStateStore.swift",
        "Stores/FieldNotesStore.swift",
        "Stores/SpeciesPreferredNameStore.swift"
    ]

    private static let expectedImportsByPath: [String: Set<String>] = [
        "AccountScopedPreferences.swift": ["import Foundation"],
        "AccountScopedRuntimeState.swift": ["import Foundation"],
        "AppSettings.swift": [
            "import Foundation",
            "import Observation",
            "import UIKit"
        ],
        "Stores/ExploreShareStateStore.swift": ["import Foundation"],
        "Stores/FieldNotesStore.swift": ["import Foundation"],
        "Stores/SpeciesPreferredNameStore.swift": ["import Foundation"]
    ]

    private static let expectedDeclarationOwners: [String: String] = [
        "enum AccountScopedPreferences":
            "apps/ios/Merian/Core/Preferences/AccountScopedPreferences.swift",
        "enum AccountScopedRuntimeState":
            "apps/ios/Merian/Core/Preferences/AccountScopedRuntimeState.swift",
        "final class AppSettings":
            "apps/ios/Merian/Core/Preferences/AppSettings.swift",
        "enum ExploreShareStateStore":
            "apps/ios/Merian/Core/Preferences/Stores/ExploreShareStateStore.swift",
        "enum FieldNotesStore":
            "apps/ios/Merian/Core/Preferences/Stores/FieldNotesStore.swift",
        "struct SpeciesPreferredNameSyncDiagnostics":
            "apps/ios/Merian/Core/Preferences/Stores/SpeciesPreferredNameStore.swift",
        "enum SpeciesPreferredNameStore":
            "apps/ios/Merian/Core/Preferences/Stores/SpeciesPreferredNameStore.swift"
    ]

    private func preferencesRoot() throws -> URL {
        try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Core/Preferences"
        )
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

    private func contents(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }

    private func swiftFiles(below root: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys)
        ) else { return [] }

        return try enumerator.compactMap { element in
            guard let file = element as? URL,
                  file.pathExtension == "swift",
                  try file.resourceValues(forKeys: keys).isRegularFile == true
            else { return nil }
            return file
        }
    }
}
