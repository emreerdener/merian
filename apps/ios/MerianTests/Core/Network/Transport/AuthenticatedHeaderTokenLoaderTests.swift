import Foundation
import Testing
@testable import Merian

@MainActor struct AuthenticatedHeaderTokenLoaderTests {
    @Test func expectedAccountFailureCannotBootstrapOrDrainItsOwnLease() async {
        var loads = 0, bootstraps = 0
        await #expect(throws: URLError.self) {
            try await AuthenticatedHeaderTokenLoader.load(expectedUserID: UUID(), load: {
                loads += 1; throw URLError(.userAuthenticationRequired)
            }, bootstrap: { bootstraps += 1; return true })
        }
        #expect(loads == 1 && bootstraps == 0)
    }
    @Test func sameAccountTokenRefreshRemainsAllowed() async throws {
        let token = try await AuthenticatedHeaderTokenLoader.load(expectedUserID: UUID(),
            load: { await Task.yield(); return "synthetic-token" },
            bootstrap: { Issue.record("Unexpected account replacement"); return true })
        #expect(token == "synthetic-token")
    }
    @Test func unownedBootstrapPolicyIsPreserved() async throws {
        var loads = 0, bootstraps = 0
        let token = try await AuthenticatedHeaderTokenLoader.load(expectedUserID: nil, load: {
            loads += 1
            if loads == 1 { throw URLError(.userAuthenticationRequired) }
            return "synthetic-token"
        }, bootstrap: { bootstraps += 1; return true })
        #expect(loads == 2 && bootstraps == 1 && token == "synthetic-token")
    }
}
