import Foundation
@testable import Merian
import Testing

@Suite("Keychain key registry")
struct KeychainKeysTests {
    @Test func appOwnedKeyStringsRemainCompatible() {
        let compiledValues = [
            "hasAuthenticatedOAuth": KeychainKeys.hasAuthenticatedOAuth,
            "legacyGhostModeUserID": KeychainKeys.legacyGhostModeUserID,
            "pendingGhostProfileMerge": KeychainKeys.pendingGhostProfileMerge,
            "pendingSignOutPurchaseHandoff":
                KeychainKeys.pendingSignOutPurchaseHandoff,
            "purchasePrincipalInstallationCapability":
                KeychainKeys.purchasePrincipalInstallationCapability,
            "purchasePrincipalBindingIntentGeneration":
                KeychainKeys.purchasePrincipalBindingIntentGeneration,
            "purchasePrincipalStableActivationFingerprint":
                KeychainKeys.purchasePrincipalStableActivationFingerprint,
            "pendingPurchasePrincipalAuthRotation":
                KeychainKeys.pendingPurchasePrincipalAuthRotation,
            "accountDeletionRecoveryCapability":
                KeychainKeys.accountDeletionRecoveryCapability,
            "analyticsRevocationIntent": KeychainKeys.analyticsRevocationIntent
        ]

        #expect(compiledValues == Self.expectedValues)
    }

    @Test func registryInventoryIsExact() throws {
        let source = try String(
            contentsOf: try registryURL(),
            encoding: .utf8
        )
        let pattern = #"static let\s+([A-Za-z0-9_]+)\s*=\s*\"([^\"]+)\""#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(source.startIndex..., in: source)
        let entries = try regex.matches(in: source, range: range).map { match in
            let nameRange = try #require(Range(match.range(at: 1), in: source))
            let valueRange = try #require(Range(match.range(at: 2), in: source))
            return (String(source[nameRange]), String(source[valueRange]))
        }

        #expect(Dictionary(uniqueKeysWithValues: entries) == Self.expectedValues)
    }

    private static let expectedValues = [
        "hasAuthenticatedOAuth": "Merian_HasAuthenticatedOAuth",
        "legacyGhostModeUserID": "Merian_GhostModeUserID_v1",
        "pendingGhostProfileMerge": "Merian_PendingGhostProfileMerge",
        "pendingSignOutPurchaseHandoff":
            "Merian_PendingSignOutPurchaseHandoff_v1",
        "purchasePrincipalInstallationCapability":
            "Merian_PurchasePrincipalInstallationCapability_v1",
        "purchasePrincipalBindingIntentGeneration":
            "Merian_PurchasePrincipalBindingIntentGeneration_v1",
        "purchasePrincipalStableActivationFingerprint":
            "Merian_PurchasePrincipalStableActivationFingerprint_v1",
        "pendingPurchasePrincipalAuthRotation":
            "Merian_PendingPurchasePrincipalAuthRotation_v1",
        "accountDeletionRecoveryCapability":
            "Merian_AccountDeletionRecoveryCapability_v1",
        "analyticsRevocationIntent": "Merian_AnalyticsRevocationIntent_v1"
    ]

    private func registryURL() throws -> URL {
        try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Core/Security/KeychainKeys.swift"
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
}
