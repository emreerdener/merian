import Foundation
import Testing

@Suite("RevenueCat Architecture")
struct RevenueCatArchitectureTests {
    @Test func ownersAreSeparatedFromLiveManager() throws {
        let root = try repositoryRoot()
        let securityRoot = root.appendingPathComponent(
            "apps/ios/Merian/Core/Security"
        )
        let revenueCatRoot = securityRoot.appendingPathComponent("RevenueCat")
        let manager = try source(
            at: securityRoot.appendingPathComponent("RevenueCatManager.swift")
        )
        let handoffStart = try #require(
            manager.range(of: "func synchronizePurchasesAfterIdentityHandoff(")
        )
        let handoffEnd = try #require(
            manager.range(
                of: "func synchronizePurchasesAfterAccountMerge(",
                range: handoffStart.upperBound..<manager.endIndex
            )
        )
        let handoffSynchronization = String(
            manager[handoffStart.lowerBound..<handoffEnd.lowerBound]
        )
        let synchronizationCall = try #require(
            handoffSynchronization.range(of: "Purchases.shared.syncPurchases()")
        )
        let beforeSynchronization = handoffSynchronization[
            ..<synchronizationCall.lowerBound
        ]
        let afterSynchronization = handoffSynchronization[
            synchronizationCall.upperBound...
        ]
        let models = try source(
            at: revenueCatRoot.appendingPathComponent(
                "Models/RevenueCatModels.swift"
            )
        )
        let identityCoordinator = try source(
            at: revenueCatRoot.appendingPathComponent(
                "Coordinators/RevenueCatIdentityCoordinator.swift"
            )
        )
        let accessPolicies = try source(
            at: revenueCatRoot.appendingPathComponent(
                "Policies/RevenueCatAccessPolicies.swift"
            )
        )
        let identityPolicies = try source(
            at: revenueCatRoot.appendingPathComponent(
                "Policies/RevenueCatIdentityPolicies.swift"
            )
        )
        let privacyPolicies = try source(
            at: revenueCatRoot.appendingPathComponent(
                "Policies/RevenueCatPrivacyPolicies.swift"
            )
        )
        let securitySources = try swiftFiles(below: securityRoot).map {
            try source(at: $0)
        }

        let actualPaths = try Set(
            swiftFiles(below: revenueCatRoot).map {
                String($0.path.dropFirst(revenueCatRoot.path.count + 1))
            }
        )
        #expect(actualPaths == Self.ownerPaths)

        let ownership: [(String, String)] = [
            ("class RevenueCatIdentityCoordinator", identityCoordinator),
            ("struct SevenDayPassPurchase", models),
            ("struct RevenueCatProviderOperationContext", models),
            ("struct RevenueCatIdentityRequest", models),
            ("struct RevenueCatIdentityLinkContext", models),
            ("enum RevenueCatLegacySubscriberAttributeKey", models),
            ("enum RevenueCatManagerError", models),
            ("struct RevenueCatIdentityContext", models),
            ("enum SevenDayPassAccessPolicy", accessPolicies),
            ("enum RevenueCatOfferingPolicy", accessPolicies),
            ("enum RevenueCatCustomerInfoVerificationPolicy", accessPolicies),
            ("enum RevenueCatEntitlementProvenancePolicy", accessPolicies),
            ("enum RevenueCatAppUserIDPolicy", identityPolicies),
            ("enum RevenueCatAccountMutationPolicy", identityPolicies),
            ("enum RevenueCatPurchaseMutationPolicy", identityPolicies),
            ("enum RevenueCatIdentityRebindPolicy", identityPolicies),
            ("enum RevenueCatSDKLogPrivacyPolicy", privacyPolicies),
            ("enum RevenueCatStableIdentityPrivacyPolicy", privacyPolicies)
        ]
        for (declaration, owner) in ownership {
            #expect(containsDeclaration(declaration, in: owner))
            #expect(
                securitySources.filter {
                    containsDeclaration(declaration, in: $0)
                }.count == 1
            )
        }

        let productionSource = [
            manager,
            models,
            accessPolicies,
            identityPolicies,
            privacyPolicies
        ].joined(separator: "\n")
        for attributeKey in Self.legacySubscriberAttributeKeys {
            #expect(
                occurrenceCount(
                    of: "\"\(attributeKey)\"",
                    in: productionSource
                ) == 1
            )
        }

        #expect(!models.contains("import RevenueCat"))
        #expect(!identityPolicies.contains("import RevenueCat"))
        #expect(!identityCoordinator.contains("import RevenueCat"))
        for forbiddenDependency in [
            "Purchases.",
            "MerianLog",
            "SupabaseManager",
            "EntitlementManager",
            "HardwareOrchestrator",
            "UIKit"
        ] {
            #expect(!identityCoordinator.contains(forbiddenDependency))
        }
        #expect(identityCoordinator.contains("@Observable"))
        #expect(identityCoordinator.contains("Task { @MainActor"))
        #expect(manager.contains("RevenueCatIdentityCoordinator()"))
        #expect(manager.contains("currentProviderOperationContext()"))
        #expect(
            beforeSynchronization.contains(
                "let context = identityCoordinator.providerOperationContext("
            )
        )
        #expect(
            afterSynchronization.contains(
                "identityCoordinator.providerOperationContext("
            )
        )
        #expect(afterSynchronization.contains(") == context"))
        #expect(
            manager.components(
                separatedBy: "isCurrentProviderOperation(context)"
            ).count >= 6
        )
        #expect(!manager.contains("guard isIdentityReady else { return }"))
        for relocatedState in [
            "requestedAppUserID",
            "requestedAuthUserID",
            "requestedBindingGeneration",
            "requestedAccountKind",
            "requestGeneration",
            "accountGrantFenceGeneration",
            "linkTaskID"
        ] {
            #expect(identityCoordinator.contains(relocatedState))
            #expect(!manager.contains(relocatedState))
        }
        for retiredManagerState in [
            "identityLinkTask",
            "identityLinkTaskId",
            "identityRequestGeneration"
        ] {
            #expect(!manager.contains(retiredManagerState))
        }
        for deterministicOwner in [
            models,
            accessPolicies,
            identityPolicies,
            privacyPolicies
        ] {
            for forbiddenDependency in [
                "Observation",
                "UIKit",
                "Purchases.",
                "MerianLog",
                "SupabaseManager",
                "EntitlementManager",
                "HardwareOrchestrator"
            ] {
                #expect(!deterministicOwner.contains(forbiddenDependency))
            }
            #expect(
                deterministicOwner.range(
                    of: #"\bTask\s*[.<({]"#,
                    options: .regularExpression
                ) == nil
            )
            #expect(!deterministicOwner.contains("withTaskGroup"))
            #expect(!deterministicOwner.contains("withThrowingTaskGroup"))
        }

        for file in try swiftFiles(below: revenueCatRoot) {
            let lineCount = try source(at: file).split(
                separator: "\n",
                omittingEmptySubsequences: false
            ).count
            #expect(lineCount <= 200, "\(file.lastPathComponent) has \(lineCount) lines")
        }
        let managerLineCount = manager.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).count
        #expect(managerLineCount <= 600)
    }

    private static let ownerPaths: Set<String> = [
        "Coordinators/RevenueCatIdentityCoordinator.swift",
        "Models/RevenueCatModels.swift",
        "Policies/RevenueCatAccessPolicies.swift",
        "Policies/RevenueCatIdentityPolicies.swift",
        "Policies/RevenueCatPrivacyPolicies.swift"
    ]

    private static let legacySubscriberAttributeKeys = [
        "supabase_user_id",
        "auth_email",
        "display_name",
        "avatar_url",
        "public_username",
        "public_author_name",
        "public_identity_source",
        "account_kind"
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
