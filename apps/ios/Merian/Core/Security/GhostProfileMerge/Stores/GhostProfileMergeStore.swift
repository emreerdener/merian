import Foundation

enum GhostProfileMergeStoreError: Error {
    case persistenceFailed
}

@MainActor
struct GhostProfileMergeStore {
    struct Dependencies {
        let loadData: (String) throws -> Data?
        let persistData: (
            Data,
            String,
            KeychainManager.Accessibility
        ) -> Bool
        let removeDataVerified: (String) throws -> Void

        static func live(keychain: KeychainManager) -> Self {
            Self(
                loadData: { key in
                    try keychain.dataOrThrow(forKey: key)
                },
                persistData: { data, key, accessibility in
                    keychain.set(
                        data,
                        forKey: key,
                        accessibility: accessibility
                    )
                },
                removeDataVerified: { key in
                    try keychain.removeObjectVerified(forKey: key)
                }
            )
        }
    }

    struct LoadResult: Equatable {
        let handoffs: [PendingGhostProfileMerge]
        let legacyMigrationWasDeferred: Bool
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func loadPendingHandoffs() throws -> LoadResult {
        let key = KeychainKeys.pendingGhostProfileMerge
        guard let data = try dependencies.loadData(key) else {
            return LoadResult(
                handoffs: [],
                legacyMigrationWasDeferred: false
            )
        }

        if let queue = try? JSONDecoder().decode(
            PendingGhostProfileMergeQueue.self,
            from: data
        ), queue.version == 1,
           queue.handoffs.allSatisfy(Self.isValid) {
            return LoadResult(
                handoffs: queue.handoffs,
                legacyMigrationWasDeferred: false
            )
        }

        // The first durable format stored a single record. Keep that proof
        // usable even when its best-effort envelope migration cannot be
        // verified; the next read retries the migration.
        if let legacy = try? JSONDecoder().decode(
            PendingGhostProfileMerge.self,
            from: data
        ), Self.isValid(legacy) {
            do {
                try persistPendingHandoffs([legacy])
                return LoadResult(
                    handoffs: [legacy],
                    legacyMigrationWasDeferred: false
                )
            } catch {
                return LoadResult(
                    handoffs: [legacy],
                    legacyMigrationWasDeferred: true
                )
            }
        }

        throw GhostProfileMergeStoreError.persistenceFailed
    }

    func persistPendingHandoffs(
        _ handoffs: [PendingGhostProfileMerge]
    ) throws {
        guard handoffs.allSatisfy(Self.isValid) else {
            throw GhostProfileMergeStoreError.persistenceFailed
        }
        if handoffs.isEmpty {
            try dependencies.removeDataVerified(
                KeychainKeys.pendingGhostProfileMerge
            )
            return
        }

        let encoded = try JSONEncoder().encode(
            PendingGhostProfileMergeQueue(handoffs: handoffs)
        )
        let key = KeychainKeys.pendingGhostProfileMerge
        guard dependencies.persistData(
            encoded,
            key,
            .whenUnlockedThisDeviceOnly
        ), try dependencies.loadData(key) == encoded else {
            throw GhostProfileMergeStoreError.persistenceFailed
        }
    }

    func clearPendingHandoff(handoffId: String) throws {
        let remaining = try loadPendingHandoffs().handoffs.filter {
            $0.handoffId.caseInsensitiveCompare(handoffId) != .orderedSame
        }
        try persistPendingHandoffs(remaining)
    }

    func clearPendingHandoffs(
        ghostUserId: String
    ) throws -> [PendingGhostProfileMerge] {
        let remaining = try loadPendingHandoffs().handoffs.filter {
            $0.ghostUserId.caseInsensitiveCompare(ghostUserId) != .orderedSame
        }
        try persistPendingHandoffs(remaining)
        return remaining
    }

    private static func isValid(
        _ pending: PendingGhostProfileMerge
    ) -> Bool {
        UUID(uuidString: pending.ghostUserId) != nil
            && (pending.provider == "apple" || pending.provider == "google")
            && isValidProviderSubject(pending.providerSubject)
            && UUID(uuidString: pending.handoffId) != nil
            && pending.handoffSecret.range(
                of: #"^[A-Za-z0-9_-]{43}$"#,
                options: .regularExpression
            ) != nil
            && isValidServerTimestamp(pending.expiresAt)
    }

    private static func isValidProviderSubject(_ value: String) -> Bool {
        guard (1...255).contains(value.utf16.count) else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return value > 0x1F
                && value != 0x7F
                && !(0x80...0x9F).contains(value)
        }
    }

    private static func isValidServerTimestamp(_ value: String) -> Bool {
        guard (20...40).contains(value.utf8.count) else { return false }
        return DateUtilities.iso8601FractionalFormatter.date(from: value) != nil
            || DateUtilities.iso8601Formatter.date(from: value) != nil
    }
}
