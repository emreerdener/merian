import Foundation
import Testing

@Suite("Core Species Preferences Architecture")
struct SpeciesPreferencesArchitectureTests {
    @Test func productionInventoryAndImportsAreExact() throws {
        let root = try speciesPreferencesRoot()
        let actualPaths = try Set(swiftFiles(below: root).map {
            $0.path.replacingOccurrences(of: root.path + "/", with: "")
        })

        #expect(actualPaths == Self.expectedProductionPaths)
        #expect(Set(Self.expectedImportsByPath.keys) == actualPaths)

        for file in try swiftFiles(below: root) {
            let relativePath = file.path.replacingOccurrences(
                of: root.path + "/",
                with: ""
            )
            let source = try contents(of: file)
            let imports = Set(
                source.split(separator: "\n")
                    .map(String.init)
                    .filter { $0.hasPrefix("import ") }
            )
            #expect(
                imports == Self.expectedImportsByPath[relativePath],
                "\(relativePath) has an unexpected framework dependency"
            )
        }
    }

    @Test func declarationsHaveOneDomainOwner() throws {
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
        #expect(!aggregate.contains("import Supabase"))
        #expect(!aggregate.contains("import SwiftData"))
        #expect(imports(in: aggregate) == ["import Foundation"])
        #expect(lineCount(of: aggregate) <= 600)
    }

    @Test func filesStayBoundedAndSupabaseResolutionStaysInClient() throws {
        let root = try speciesPreferencesRoot()
        for file in try swiftFiles(below: root) {
            let relativePath = file.path.replacingOccurrences(
                of: root.path + "/",
                with: ""
            )
            let source = try contents(of: file)
            #expect(
                lineCount(of: source) <= 600,
                "\(relativePath) exceeds the 600-line review ceiling"
            )
            #expect(!source.contains("AppDIContainer"))
            #expect(!source.contains("URLSession"))

            if relativePath != Self.cloudClientPath {
                #expect(!source.contains("SupabaseManager.shared"))
                #expect(!source.contains("import Supabase"))
                #expect(!source.contains(".from(\""))
            }
        }

        let client = try contents(
            of: root.appendingPathComponent(Self.cloudClientPath)
        )
        #expect(client.contains("SupabaseManager.shared"))
        #expect(client.contains(".from(\"user_species_preferences\")"))
        #expect(
            client.contains(
                "scientific_name, preferred_common_name, updated_at, deleted_at"
            )
        )
        #expect(client.contains(".gt(\"scientific_name\", value: cursor)"))
        #expect(
            client.contains(".order(\"scientific_name\", ascending: true)")
        )
        #expect(client.contains(".limit(request.pageSize)"))
        #expect(!client.contains(".range("))
        #expect(client.contains("user_id,scientific_name"))
        #expect(
            client.components(separatedBy: ".execute()").count - 1 == 2,
            "The paginated read and upsert must each execute exactly once"
        )
    }

    private static let cloudClientPath =
        "Services/SpeciesPreferredNameCloudClient.swift"

    private static let expectedProductionPaths: Set<String> = [
        "Models/SpeciesPreferenceCloudModels.swift",
        "Models/SpeciesNameMigrationResult.swift",
        "Services/SpeciesPreferredNameCloudClient.swift",
        "Services/SpeciesPreferredNameCloudSyncCoordinator.swift",
        "Services/SpeciesPreferenceLocalRecovery.swift",
        "SpeciesPreferredNamePolicy.swift",
        "SpeciesPreferredNameRepository.swift"
    ]

    private static let expectedImportsByPath: [String: Set<String>] = [
        "Models/SpeciesPreferenceCloudModels.swift": ["import Foundation"],
        "Models/SpeciesNameMigrationResult.swift": ["import Foundation"],
        "Services/SpeciesPreferredNameCloudClient.swift": [
            "import Foundation",
            "import Supabase"
        ],
        "Services/SpeciesPreferredNameCloudSyncCoordinator.swift": [
            "import Foundation",
            "import SwiftData"
        ],
        "Services/SpeciesPreferenceLocalRecovery.swift": [
            "import Foundation",
            "import SwiftData"
        ],
        "SpeciesPreferredNamePolicy.swift": ["import Foundation"],
        "SpeciesPreferredNameRepository.swift": [
            "import Foundation",
            "import SwiftData"
        ]
    ]

    private static let expectedDeclarationOwners: [String: String] = [
        "struct SpeciesNameMigrationResult":
            "apps/ios/Merian/Core/Data/SpeciesPreferences/Models/SpeciesNameMigrationResult.swift",
        "struct SpeciesPreferenceCloudRow":
            "apps/ios/Merian/Core/Data/SpeciesPreferences/Models/SpeciesPreferenceCloudModels.swift",
        "struct SpeciesPreferenceCloudUpsert":
            "apps/ios/Merian/Core/Data/SpeciesPreferences/Models/SpeciesPreferenceCloudModels.swift",
        "enum SpeciesPreferredNameResourceLimits":
            "apps/ios/Merian/Core/Data/SpeciesPreferences/SpeciesPreferredNamePolicy.swift",
        "enum SpeciesPreferredNamePolicy":
            "apps/ios/Merian/Core/Data/SpeciesPreferences/SpeciesPreferredNamePolicy.swift",
        "enum SpeciesPreferredNameRepository":
            "apps/ios/Merian/Core/Data/SpeciesPreferences/SpeciesPreferredNameRepository.swift",
        "struct SpeciesPreferredNameCloudClient":
            "apps/ios/Merian/Core/Data/SpeciesPreferences/Services/SpeciesPreferredNameCloudClient.swift",
        "final class SpeciesPreferredNameCloudSyncCoordinator":
            "apps/ios/Merian/Core/Data/SpeciesPreferences/Services/SpeciesPreferredNameCloudSyncCoordinator.swift",
        "enum SpeciesPreferenceLocalRecovery":
            "apps/ios/Merian/Core/Data/SpeciesPreferences/Services/SpeciesPreferenceLocalRecovery.swift"
    ]

    private func speciesPreferencesRoot() throws -> URL {
        try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Core/Data/SpeciesPreferences"
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

    private func imports(in source: String) -> Set<String> {
        Set(
            source.split(separator: "\n")
                .map(String.init)
                .filter { $0.hasPrefix("import ") }
        )
    }

    private func lineCount(of source: String) -> Int {
        source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).count
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
