import Foundation
import Testing

@testable import Merian

struct LocalScanMediaRecoveryRevisionTests {
    @Test func revisionsTrackOnlyAffectedSourcesAndNeverReuseAnEvictedIdentity() throws {
        let registry = LocalScanMediaRecoveryRegistry()
        let guess = try source("guess")
        let paired = try source("paired")
        let exact = try source("exact")
        let unrelated = try source("unrelated")
        let initial = registry.cacheRevision(for: [guess])
        #expect(registry.registerTimestampMappings(
            remoteURLs: [guess, paired], fileNames: ["image.webp", "paired.webp"]
        ))
        let guessed = registry.cacheRevision(for: [guess])
        let pairedRevision = registry.cacheRevision(for: [paired])
        #expect(guessed > initial)
        #expect(registry.cacheRevision(for: [unrelated]) == initial)
        #expect(registry.registerStrongMapping(remoteURL: exact, fileName: "image.webp"))
        let corrected = registry.cacheRevision(for: [guess])
        #expect(corrected > guessed)
        #expect(registry.cacheRevision(for: [paired]) > pairedRevision)
        #expect(registry.fileName(for: guess) == nil)
        #expect(registry.registerStrongMapping(remoteURL: unrelated, fileName: "unrelated.webp"))
        #expect(registry.cacheRevision(for: [guess]) == corrected)
        let exactRevision = registry.cacheRevision(for: [exact])
        #expect(!registry.registerStrongMapping(remoteURL: exact, fileName: "ignored.webp"))
        #expect(registry.cacheRevision(for: [exact]) == exactRevision)
        registry.reset()
        #expect(registry.cacheRevision(for: [guess]) > corrected)
        #expect(registry.cacheRevision(for: [exact]) > exactRevision)
        #expect(registry.cacheRevision(for: []) == 0)
    }

    @Test func subscribersObserveCanonicalSourceChangesAndReset() async throws {
        let registry = LocalScanMediaRecoveryRegistry()
        let original = try source("image")
        let alias = try #require(URL(string:
            "HTTPS://MEDIA.MERIAN.APP:443/public_uploads/free/synthetic/image.webp?size=100#preview"
        ))
        var changes = registry.changes(for: [alias]).makeAsyncIterator()
        #expect(await changes.next() != nil)
        let before = registry.cacheRevision(for: [alias])
        #expect(registry.registerStrongMapping(remoteURL: original, fileName: "local.webp"))
        #expect(await changes.next() != nil)
        let registered = registry.cacheRevision(for: [alias])
        #expect(registered > before)
        #expect(registered == registry.cacheRevision(for: [original]))
        registry.reset()
        #expect(await changes.next() != nil)
        #expect(registry.cacheRevision(for: [alias]) > registered)
    }

    @Test func nonRecoverySourcesFinishWithoutRetainingASubscription() async throws {
        let registry = LocalScanMediaRecoveryRegistry()
        var changes = registry.changes(for: [
            try #require(URL(string: "https://images.example.com/photo.webp"))
        ]).makeAsyncIterator()
        #expect(await changes.next() != nil)
        #expect(await changes.next() == nil)
    }

    private func source(_ name: String) throws -> URL {
        try #require(URL(string: "https://media.merian.app/public_uploads/free/synthetic/\(name).webp"))
    }
}
