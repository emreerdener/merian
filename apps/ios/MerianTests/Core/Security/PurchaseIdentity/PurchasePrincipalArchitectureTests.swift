import Foundation
import Testing

@Suite("Purchase Principal Architecture")
struct PurchasePrincipalArchitectureTests {
    @Test func purchaseIdentityOwnersStaySeparated() throws {
        let root = try repositoryRoot()
        let securityRoot = root.appendingPathComponent(
            "apps/ios/Merian/Core/Security"
        )
        let purchaseRoot = securityRoot.appendingPathComponent(
            "PurchaseIdentity"
        )
        let resolver = try source(
            at: securityRoot.appendingPathComponent(
                "PurchasePrincipalResolver.swift"
            )
        )
        let models = try source(
            at: purchaseRoot.appendingPathComponent(
                "Models/PurchasePrincipalModels.swift"
            )
        )
        let wireModels = try source(
            at: purchaseRoot.appendingPathComponent(
                "Models/PurchasePrincipalWireModels.swift"
            )
        )
        let policies = try source(
            at: purchaseRoot.appendingPathComponent(
                "Policies/PurchasePrincipalPolicies.swift"
            )
        )
        let capabilityStore = try source(
            at: purchaseRoot.appendingPathComponent(
                "Stores/PurchasePrincipalCapabilityStore.swift"
            )
        )
        let secureStateStore = try source(
            at: purchaseRoot.appendingPathComponent(
                "Stores/PurchasePrincipalSecureStateStore.swift"
            )
        )
        let secureStore = try source(
            at: purchaseRoot.appendingPathComponent(
                "Stores/PurchasePrincipalSecureStore.swift"
            )
        )
        let remoteService = try source(
            at: purchaseRoot.appendingPathComponent(
                "Services/PurchasePrincipalRemoteService.swift"
            )
        )
        let liveRemoteService = try source(
            at: purchaseRoot.appendingPathComponent(
                "Services/PurchasePrincipalRemoteService+Live.swift"
            )
        )
        let secureRandom = try source(
            at: purchaseRoot.appendingPathComponent(
                "Services/PurchasePrincipalSecureRandom.swift"
            )
        )
        let securitySources = try swiftFiles(below: securityRoot).map {
            try source(at: $0)
        }

        let actualPaths = try Set(
            swiftFiles(below: purchaseRoot).map {
                String($0.path.dropFirst(purchaseRoot.path.count + 1))
            }
        )
        #expect(actualPaths == Self.ownerPaths)

        let ownership: [(String, String)] = [
            ("enum PurchasePrincipalResolutionMode", models),
            ("struct PurchasePrincipalBinding", models),
            ("enum PurchasePrincipalResolverError", models),
            ("struct PrincipalRotationPreparation", models),
            ("struct PrincipalRotationCancellation", models),
            ("enum PurchasePrincipalProtocol", wireModels),
            ("struct PurchasePrincipalResolveResponse", wireModels),
            ("struct PrincipalRotationPrepareResponse", wireModels),
            ("struct PrincipalRotationClaimResponse", wireModels),
            ("struct PrincipalRotationCancelResponse", wireModels),
            ("enum PurchasePrincipalCapabilityPolicy", policies),
            ("enum PurchasePrincipalBindingIntentPolicy", policies),
            ("enum PurchasePrincipalCompatibilityPolicy", policies),
            ("enum PurchasePrincipalTimestampPolicy", policies),
            ("enum PurchasePrincipalSecretPolicy", policies),
            ("struct PurchasePrincipalCapabilityStore", capabilityStore),
            ("struct PurchasePrincipalSecureStateStore", secureStateStore),
            ("protocol PurchasePrincipalSecureStore", secureStore),
            ("struct PurchasePrincipalRemoteService", remoteService),
            ("enum PurchasePrincipalSecureRandom", secureRandom),
            ("class PurchasePrincipalResolver", resolver)
        ]
        for (declaration, owner) in ownership {
            #expect(containsDeclaration(declaration, in: owner))
            #expect(
                securitySources.filter {
                    containsDeclaration(declaration, in: $0)
                }.count == 1
            )
        }

        #expect(!resolver.contains("import Supabase"))
        #expect(!resolver.contains("import Security"))
        #expect(!resolver.contains("functions.invoke"))
        #expect(!resolver.contains("KeychainManager.shared"))
        #expect(liveRemoteService.contains("import Supabase"))
        #expect(
            occurrenceCount(
                of: "client.functions.invoke(",
                in: liveRemoteService
            ) == 4
        )
        #expect(
            occurrenceCount(
                of: "\"resolve-purchase-principal\"",
                in: liveRemoteService
            ) == 4
        )
        #expect(
            liveRemoteService.contains(
                "convenience init(\n        client: SupabaseClient,"
            )
        )
        for payload in [
            "PurchasePrincipalResolvePayload",
            "PrincipalRotationPreparePayload",
            "PrincipalRotationClaimPayload",
            "PrincipalRotationCancelPayload"
        ] {
            #expect(
                liveRemoteService.contains("private struct \(payload)")
            )
        }

        for deterministicOwner in [models, wireModels, policies] {
            for forbiddenDependency in [
                "import Supabase",
                "import Security",
                "KeychainManager",
                "functions.invoke",
                "Task {"
            ] {
                #expect(!deterministicOwner.contains(forbiddenDependency))
            }
        }
        for store in [capabilityStore, secureStateStore, secureStore] {
            #expect(!store.contains("import Supabase"))
            #expect(!store.contains("functions.invoke"))
        }
        #expect(secureRandom.contains("SecRandomCopyBytes"))

        for file in try swiftFiles(below: purchaseRoot) {
            let lineCount = try source(at: file).split(
                separator: "\n",
                omittingEmptySubsequences: false
            ).count
            #expect(lineCount <= 250, "\(file.lastPathComponent) has \(lineCount) lines")
        }
        let resolverLineCount = resolver.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).count
        #expect(resolverLineCount <= 300)
    }

    private static let ownerPaths: Set<String> = [
        "Models/PurchaseIdentityHandoffModels.swift",
        "Models/PurchasePrincipalModels.swift",
        "Models/PurchasePrincipalWireModels.swift",
        "Policies/PurchasePrincipalPolicies.swift",
        "Services/PurchasePrincipalRemoteService+Live.swift",
        "Services/PurchasePrincipalRemoteService.swift",
        "Services/PurchasePrincipalSecureRandom.swift",
        "Stores/PurchaseIdentityHandoffStore.swift",
        "Stores/PurchasePrincipalCapabilityStore.swift",
        "Stores/PurchasePrincipalSecureStateStore.swift",
        "Stores/PurchasePrincipalSecureStore.swift"
    ]

    private func source(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func swiftFiles(below root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw CocoaError(.fileReadUnknown)
        }
        return try enumerator.compactMap { item in
            guard let url = item as? URL,
                  url.pathExtension == "swift",
                  try url.resourceValues(forKeys: [.isRegularFileKey])
                    .isRegularFile == true else {
                return nil
            }
            return url
        }
    }

    private func containsDeclaration(
        _ declaration: String,
        in source: String
    ) -> Bool {
        let escapedDeclaration = NSRegularExpression.escapedPattern(
            for: declaration
        )
        let pattern =
            #"(?m)^\s*(?:(?:private|fileprivate|internal|package|public|final)\s+)*"#
            + escapedDeclaration
            + #"(?:\s*[:{])"#
        return source.range(of: pattern, options: .regularExpression) != nil
    }

    private func occurrenceCount(of value: String, in source: String) -> Int {
        source.components(separatedBy: value).count - 1
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        while candidate.path != "/" {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("project.yml").path
            ) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
