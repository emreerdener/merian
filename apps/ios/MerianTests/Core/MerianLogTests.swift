@testable import Merian
import Testing

@Suite("Identity-safe logging")
struct MerianLogTests {
    private struct IdentityBearingError: Error, CustomStringConvertible {
        let description = "customer=550e8400-e29b-41d4-a716-446655440000"
    }

    @Test("Error diagnostics retain type only")
    func errorKindOmitsInstanceDescription() {
        let kind = MerianLog.errorKind(IdentityBearingError())

        #expect(kind.contains("IdentityBearingError"))
        #expect(!kind.contains("550e8400"))
        #expect(!kind.contains("customer"))
        #expect(kind.count <= 80)
    }

    @Test("Authentication and purchase logs do not interpolate identity-bearing values")
    func identitySourcesUseBoundedDiagnostics() throws {
        var repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        for _ in 0..<4 {
            repositoryRoot.deleteLastPathComponent()
        }
        let relativePaths = [
            "apps/ios/Merian/Core/Network/SupabaseManager.swift",
            "apps/ios/Merian/Core/Security/RevenueCatManager.swift",
            "apps/ios/Merian/Core/Security/ConsentManager.swift",
            "apps/ios/Merian/Core/Network/KeychainManager.swift",
            "apps/ios/Merian/Core/Network/MerianNetworkClient.swift",
            "apps/ios/Merian/Core/Analytics/PostHogManager.swift",
            "apps/ios/Merian/Core/Security/SocialGuardManager.swift"
        ]
        let sources = try relativePaths.map {
            try String(
                contentsOf: repositoryRoot.appendingPathComponent($0),
                encoding: .utf8
            )
        }

        let identitySources = sources.joined()
        for forbidden in [
            "authResponse.user.id, privacy:",
            "pending.ghostUserId, privacy:",
            "appUserID, privacy:",
            "finalUserId, privacy:",
            "identifiedUserId, privacy:",
            "targetUserId, privacy:",
            "error.localizedDescription, privacy:",
            "error, privacy:",
            "Auth event:",
            "authenticated: \\("
        ] {
            #expect(!identitySources.contains(forbidden))
        }
        #expect(!(sources.last ?? "").contains("errString, privacy:"))
    }
}
