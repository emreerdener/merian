import Foundation
import Testing

@testable import Merian

@Suite("Pinned Network Transport")
struct PinnedNetworkTransportTests {
    @Test func productionConfigurationRetainsReviewedBounds() {
        let configuration = PinnedNetworkTransport.makeConfiguration()

        #expect(configuration.timeoutIntervalForRequest == 30)
        #expect(configuration.timeoutIntervalForResource == 90)
        #expect(configuration.httpMaximumConnectionsPerHost == 6)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.urlCache == nil)
    }

    @Test func testPinnedHashesAreNonEmptyValidBase64() {
        let hashes = MerianTLSCertificatePinPolicy.pinnedCertificateHashes

        #expect(!hashes.isEmpty)
        #expect(hashes.allSatisfy { hash in
            Data(base64Encoded: hash)?.count == 32
        })
    }

    @Test func pinningMatchesOnlyTheSupabaseDomainBoundary() {
        #expect(
            MerianTLSCertificatePinPolicy.requiresPinning(
                host: "project.supabase.co"
            )
        )
        #expect(
            MerianTLSCertificatePinPolicy.requiresPinning(
                host: "SUPABASE.CO"
            )
        )
        #expect(
            MerianTLSCertificatePinPolicy.requiresPinning(
                host: "project.supabase.co."
            )
        )
        #expect(
            !MerianTLSCertificatePinPolicy.requiresPinning(
                host: "not-supabase.co"
            )
        )
        #expect(
            !MerianTLSCertificatePinPolicy.requiresPinning(
                host: "supabase.co.example.com"
            )
        )
        #expect(
            !MerianTLSCertificatePinPolicy.requiresPinning(
                host: ".supabase.co"
            )
        )
    }

    @Test func concurrentFirstUseRetainsOneProductionSession() async {
        let transport = PinnedNetworkTransport()
        let identities = await withTaskGroup(
            of: ObjectIdentifier.self,
            returning: [ObjectIdentifier].self
        ) { group in
            for _ in 0..<32 {
                group.addTask {
                    transport.productionSessionIdentityForTesting
                }
            }
            var values: [ObjectIdentifier] = []
            for await identity in group {
                values.append(identity)
            }
            return values
        }

        #expect(Set(identities).count == 1)
    }

    @Test func testTLSChainWalkingAcceptsIntermediateCertWhenLeafIsUnknown() {
        let intermediateHash =
            "HfwWBfutNY2LyET3bRUgP6ycpcGnn9SFf/ryhk++v5Y="
        #expect(
            MerianTLSCertificatePinPolicy.pinnedCertificateHashes
                .contains(intermediateHash)
        )
        let chain = [
            "rotated-leaf",
            intermediateHash,
            "untrusted-root"
        ]

        #expect(
            MerianTLSCertificatePinPolicy.accepts(
                systemTrustIsValid: true,
                certificateChainHashes: chain
            )
        )
    }

    @Test func testTLSChainWalkingRejectsUnknownChain() {
        #expect(
            !MerianTLSCertificatePinPolicy.accepts(
                systemTrustIsValid: true,
                certificateChainHashes: nil
            )
        )
        #expect(
            !MerianTLSCertificatePinPolicy.accepts(
                systemTrustIsValid: true,
                certificateChainHashes: []
            )
        )
        #expect(
            !MerianTLSCertificatePinPolicy.accepts(
                systemTrustIsValid: true,
                certificateChainHashes: [
                    "unknown-leaf",
                    "unknown-intermediate",
                    "unknown-root"
                ]
            )
        )
        #expect(
            !MerianTLSCertificatePinPolicy.accepts(
                systemTrustIsValid: false,
                certificateChainHashes: [
                    "HfwWBfutNY2LyET3bRUgP6ycpcGnn9SFf/ryhk++v5Y="
                ]
            )
        )
    }

    @Test func injectedSessionOwnsTestDispatch() async throws {
        let mockTransport = ScopedMockTransport()
        let session = mockTransport.makeSession()
        defer { session.invalidateAndCancel() }
        mockTransport.register(path: "/transport-probe") { request in
            let url = try #require(request.url)
            let response = try #require(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (response, Data("transport-ok".utf8))
        }

        let transport = PinnedNetworkTransport()
        transport.overridingSession = session
        let url = try #require(
            URL(string: "https://example.supabase.co/transport-probe")
        )
        let (data, response) = try await transport.data(
            for: URLRequest(url: url)
        )

        #expect(data == Data("transport-ok".utf8))
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }
}
