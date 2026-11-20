import Foundation

/// Qualification roots must already exist. A lock is held across the entire
/// reservation, provider callback, file commit and fresh-context ledger save.
actor PhotoPreparationFileStore {
    let root: URL
    init(root: URL) { self.root = root }

    func locked<T: Sendable>(
        _ body: @Sendable (PhotoPreparationLockedFiles) async throws -> T
    ) async throws -> T {
        let files = try PhotoPreparationLockedFiles(root: root)
        defer { files.close() }
        return try await body(files)
    }
}
