import Foundation
import Testing

@Suite("Account deletion security architecture")
struct AccountDeletionSecurityArchitectureTests {
    @Test func productionInventoryAndImportsAreExact() throws {
        let root = try accountDeletionRoot()
        let files = try swiftFiles(below: root)
        let actualPaths = Set(files.map { relativePath(of: $0, below: root) })

        #expect(actualPaths == Set(Self.expectedImportsByPath.keys))

        for file in files {
            let path = relativePath(of: file, below: root)
            let source = try contents(of: file)
            #expect(imports(in: source) == Self.expectedImportsByPath[path])
            #expect(
                lineCount(source) <= 600,
                "\(path) exceeds the 600-line review ceiling"
            )
        }
    }

    @Test func declarationsHaveFocusedOwners() throws {
        let root = try repositoryRoot()
        let coreRoot = root.appendingPathComponent("apps/ios/Merian/Core")
        let sources = try Dictionary(uniqueKeysWithValues: swiftFiles(
            below: coreRoot
        ).map { file in
            (
                relativePath(of: file, below: root),
                try contents(of: file)
            )
        })

        for (declaration, expectedPath) in Self.expectedDeclarationOwners {
            let owners = sources.compactMap { path, source in
                source.contains(declaration) ? path : nil
            }
            #expect(owners == [expectedPath])
        }
    }

    @Test func modelsRemainEffectFreeAndStoresRemainLocal() throws {
        let root = try accountDeletionRoot()
        let modelsRoot = root.appendingPathComponent("Models")
        for file in try swiftFiles(below: modelsRoot) {
            let source = try contents(of: file)
            for forbidden in [
                "AppDIContainer",
                "KeychainManager",
                "Supabase",
                "URLSession",
                "UserDefaults"
            ] {
                #expect(
                    !source.contains(forbidden),
                    "\(file.lastPathComponent) resolves \(forbidden)"
                )
            }
        }

        let storesRoot = root.appendingPathComponent("Stores")
        for file in try swiftFiles(below: storesRoot) {
            let source = try contents(of: file)
            for forbidden in [
                "import Supabase",
                "MerianNetworkClient",
                "URLSession",
                ".from(\"",
                ".rpc("
            ] {
                #expect(
                    !source.contains(forbidden),
                    "\(file.lastPathComponent) resolves \(forbidden)"
                )
            }
        }
    }

    @Test func retiredOwnersAreAbsentAndTestsAreSecurityOwned() throws {
        let root = try repositoryRoot()
        for path in Self.retiredPaths {
            #expect(
                !FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(path).path
                )
            )
        }

        let appDITests = try contents(
            of: root.appendingPathComponent(
                "apps/ios/MerianTests/Core/AppDIContainerTests.swift"
            )
        )
        for declaration in [
            "ManualAppleRevocationNoticeStore",
            "AccountDeletionLocalCleanupStore"
        ] {
            #expect(!appDITests.contains(declaration))
        }

        let testRoot = root.appendingPathComponent(
            "apps/ios/MerianTests/Core/Security/AccountDeletion"
        )
        let actualTestPaths = try Set(swiftFiles(below: testRoot).map {
            relativePath(of: $0, below: testRoot)
        })
        #expect(actualTestPaths == Self.expectedTestPaths)
    }

    private static let expectedImportsByPath: [String: Set<String>] = [
        "Models/AccountDeletionLocalRecoveryState.swift": [],
        "Models/AccountDeletionRecoveryCapabilityModels.swift": [
            "import Foundation"
        ],
        "Stores/AccountDeletionLocalCleanupStore.swift": [
            "import Foundation"
        ],
        "Stores/AccountDeletionRecoveryCapabilityStore.swift": [
            "import Foundation",
            "import Security"
        ],
        "Stores/ManualAppleRevocationNoticeStore.swift": [
            "import Foundation"
        ]
    ]

    private static let expectedDeclarationOwners: [String: String] = [
        "enum AccountDeletionLocalRecoveryState":
            "apps/ios/Merian/Core/Security/AccountDeletion/Models/" +
            "AccountDeletionLocalRecoveryState.swift",
        "enum AccountDeletionRecoveryCapabilityError":
            "apps/ios/Merian/Core/Security/AccountDeletion/Models/" +
            "AccountDeletionRecoveryCapabilityModels.swift",
        "struct PreparedDeletionRecoveryCapability":
            "apps/ios/Merian/Core/Security/AccountDeletion/Models/" +
            "AccountDeletionRecoveryCapabilityModels.swift",
        "enum AccountDeletionLocalCleanupStore":
            "apps/ios/Merian/Core/Security/AccountDeletion/Stores/" +
            "AccountDeletionLocalCleanupStore.swift",
        "protocol AccountDeletionRecoverySecureStore":
            "apps/ios/Merian/Core/Security/AccountDeletion/Stores/" +
            "AccountDeletionRecoveryCapabilityStore.swift",
        "struct AccountDeletionRecoveryCapabilityStore":
            "apps/ios/Merian/Core/Security/AccountDeletion/Stores/" +
            "AccountDeletionRecoveryCapabilityStore.swift",
        "enum ManualAppleRevocationNoticeStore":
            "apps/ios/Merian/Core/Security/AccountDeletion/Stores/" +
            "ManualAppleRevocationNoticeStore.swift",
        "enum KeychainKeys":
            "apps/ios/Merian/Core/Security/KeychainKeys.swift"
    ]

    private static let expectedTestPaths: Set<String> = [
        "AccountDeletionLocalCleanupStoreTests.swift",
        "AccountDeletionRecoveryCapabilityStoreTests.swift",
        "AccountDeletionSecurityArchitectureTests.swift",
        "ManualAppleRevocationNoticeStoreTests.swift"
    ]

    private static let retiredPaths = [
        "apps/ios/Merian/Core/Security/AccountDeletionRecoveryCapability.swift",
        "apps/ios/Merian/Core/Utilities/UserDefaultsKeys.swift",
        "apps/ios/MerianTests/Core/Security/" +
            "AccountDeletionRecoveryCapabilityTests.swift"
    ]

    private func accountDeletionRoot() throws -> URL {
        try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Core/Security/AccountDeletion"
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

    private func lineCount(_ source: String) -> Int {
        source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).count
    }

    private func relativePath(of file: URL, below root: URL) -> String {
        file.path.replacingOccurrences(of: root.path + "/", with: "")
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
