import Foundation

/// Token loading may refresh the same SDK session. It must never replace the
/// identity of work that already holds an exact account's native/media leases.
@MainActor
enum AuthenticatedHeaderTokenLoader {
    static func load(expectedUserID: UUID?, load: () async throws -> String,
                     bootstrap: () async throws -> Bool) async throws -> String {
        do { return try await load() } catch {
            // Bootstrap drains account work. Calling it from an exact-account
            // request would recursively wait for that request's retained lease.
            guard expectedUserID == nil else { throw error }
            guard try await bootstrap() else { throw error }
            return try await load()
        }
    }
}
