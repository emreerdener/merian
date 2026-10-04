import Foundation

/// Device-only recovery intent, committed before the first destructive step.
/// No session credentials or library contents are copied into this journal.
struct LibrarySignOutJournal: Codable, Equatable {
    enum Phase: String, Codable {
        case committed
        case sourceCleared
        case libraryCleared
        case destinationCreated
    }

    let version: Int
    let sourceUserID: UUID
    var phase: Phase
    var destinationUserID: UUID?

    init(sourceUserID: UUID) {
        version = 1
        self.sourceUserID = sourceUserID
        phase = .committed
    }
}

@MainActor
struct LibrarySignOutJournalStore {
    struct Dependencies {
        var read: () throws -> Data?
        var write: (Data) -> Bool
        var remove: () throws -> Void
    }

    let dependencies: Dependencies

    static var live: Self {
        let key = KeychainKeys.librarySignOutJournal
        let keychain = KeychainManager.shared
        return Self(dependencies: Dependencies(
            read: { try keychain.dataOrThrow(forKey: key) },
            write: { keychain.set($0, forKey: key, accessibility: .whenUnlockedThisDeviceOnly) },
            remove: { try keychain.removeObjectVerified(forKey: key) }
        ))
    }

    func load() throws -> LibrarySignOutJournal? {
        guard let data = try dependencies.read() else { return nil }
        let journal = try JSONDecoder().decode(LibrarySignOutJournal.self, from: data)
        guard journal.version == 1,
              journal.destinationUserID != journal.sourceUserID,
              (journal.phase == .destinationCreated) == (journal.destinationUserID != nil) else {
            throw KeychainManager.AccessError.verificationFailed
        }
        return journal
    }

    func save(_ journal: LibrarySignOutJournal) throws {
        let data = try JSONEncoder().encode(journal)
        guard dependencies.write(data), try dependencies.read() == data else {
            throw KeychainManager.AccessError.verificationFailed
        }
        _ = try load()
    }

    func clear() throws {
        try dependencies.remove()
        guard try dependencies.read() == nil else {
            throw KeychainManager.AccessError.verificationFailed
        }
    }

    var isPending: Bool {
        do { return try load() != nil } catch { return true }
    }
}

/// Ownership of the unpartitioned local library survives session expiration.
/// This is an isolation marker, never an authentication credential.
@MainActor
enum LibraryAccountOwnerStore {
    static func load() throws -> UUID? {
        guard let data = try KeychainManager.shared.dataOrThrow(forKey: KeychainKeys.libraryAccountOwner) else { return nil }
        return try JSONDecoder().decode(UUID.self, from: data)
    }

    static func save(_ owner: UUID) throws {
        let data = try JSONEncoder().encode(owner)
        guard KeychainManager.shared.set(data, forKey: KeychainKeys.libraryAccountOwner, accessibility: .whenUnlockedThisDeviceOnly),
              try load() == owner else { throw KeychainManager.AccessError.verificationFailed }
    }

    static func clear() throws {
        try KeychainManager.shared.removeObjectVerified(forKey: KeychainKeys.libraryAccountOwner)
    }
}

enum LibraryAccountOwnershipPolicy {
    static func requiresRecovery(owner: UUID, session: UUID?, libraryIsEmpty: Bool) -> Bool {
        owner != session && !libraryIsEmpty
    }

    /// Older installations may have a merge proof but no library marker yet.
    /// Such a proof identifies the source; it never authorizes destination
    /// ownership before the server acknowledges the transfer.
    static func canAdoptUnmarkedLibrary(session: UUID?, pendingSourceIDs: [String]) -> Bool {
        guard !pendingSourceIDs.isEmpty else { return true }
        guard let session else { return false }
        return pendingSourceIDs.allSatisfy { UUID(uuidString: $0) == session }
    }
}
