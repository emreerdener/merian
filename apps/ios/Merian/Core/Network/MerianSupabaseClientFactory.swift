import CryptoKit
import Foundation
import os
import Security
import Supabase

enum MerianSupabaseClientFactory {
    static func makeClient(
        emitLocalSessionAsInitialSession: Bool = true,
        session: URLSession = .shared
    ) -> SupabaseClient {
        MerianEnvironment.requireHistoryQualificationConfiguration()
        let url = SecureTransportPolicy.httpsURL(
            from: MerianEnvironment.supabaseUrl
        ) ?? SecureTransportPolicy.httpsURL(
            from: MerianEnvironment.fallbackSupabaseURL
        )!
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: MerianEnvironment.supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: .init(
                    storage: makeAuthStorage(),
                    storageKey: MerianEnvironment.isHistoryQualificationBuild ? QualificationAuthStorage.sessionKey : nil,
                    emitLocalSessionAsInitialSession: emitLocalSessionAsInitialSession
                ),
                global: .init(
                    // History reads bypass the inference transports. Every SDK
                    // request must retain the same truthful reader capability.
                    headers: [IdentificationDispatchAuthorization.protocolHeader:
                        String(IdentificationDispatchAuthorization.currentProtocol)],
                    session: session
                )
            )
        )
    }

    static func beginQualificationExchange(_ attempt: UUID) throws -> QualificationAuthStorage? {
        guard MerianEnvironment.isHistoryQualificationBuild else { return nil }
        guard let scope = MerianEnvironment.historyQualificationScope else {
            throw MerianEnvironment.HistoryQualificationFailure.accounts
        }
        let storage = QualificationAuthStorage(storage: QualificationKeychainStorage(), scope: scope)
        try storage.begin(attempt)
        return storage
    }

    static func makeAuthStorage() -> any AuthLocalStorage {
        #if DEBUG
        if TestExecutionCoordinator.isRunningTests {
            return ProcessLocalAuthStorage()
        }
        #endif
        if MerianEnvironment.isHistoryQualificationBuild {
            guard let scope = MerianEnvironment.historyQualificationScope else {
                fatalError("Qualification Auth storage requires a validated scope.")
            }
            return QualificationAuthStorage(storage: QualificationKeychainStorage(), scope: scope)
        }
        return KeychainLocalStorage()
    }
}

/// The pending envelope exposes only the prior approved session. SDK writes and
/// removals cannot settle an exchange; only the synchronous exact-attempt commit
/// may create an acceptance receipt. Failed/uncertain state is never downgraded
/// to ordinary account allowlisting, including after process death.
struct QualificationAuthStorage: AuthLocalStorage {
    static let sessionKey = "history-qualification-session"
    private static let transactionLock = OSAllocatedUnfairLock()
    let storage: any AuthLocalStorage
    let scope: MerianEnvironment.HistoryQualificationScope

    enum SettlementFailure: Error, Equatable { case notAccepted, unresolved }
    private struct Receipt: Codable {
        let attempt: UUID
        let acceptedBytes: Data
        let digest: String
        let evidence: MerianEnvironment.HistoryQualificationIdentityEvidence
        let acceptedAt: Date
    }
    private struct Envelope: Codable {
        var version = 1
        var approved: Data?
        var pending: UUID?
        var receipt: Receipt?
    }

    func store(key: String, value: Data) throws {
        try Self.transactionLock.withLock {
            guard key == Self.sessionKey else { throw SettlementFailure.notAccepted }
            let incoming = try session(value)
            var envelope = try load()
            guard envelope.pending == nil, let approved = envelope.approved,
                  try session(approved).user.id == incoming.user.id else { throw SettlementFailure.notAccepted }
            envelope.approved = value // Same-account SDK refresh preserves acceptance provenance.
            try writeConfirmed(envelope)
        }
    }

    func retrieve(key: String) throws -> Data? {
        guard key == Self.sessionKey else { return nil }
        return try Self.transactionLock.withLock { try load().approved }
    }

    func remove(key: String) throws {
        guard key == Self.sessionKey else { return }
        try Self.transactionLock.withLock {
            let envelope = try load()
            guard envelope.pending == nil else { throw SettlementFailure.notAccepted }
            if envelope.approved != nil { try storage.remove(key: key) }
        }
    }

    func begin(_ attempt: UUID) throws {
        try Self.transactionLock.withLock {
            var envelope = try load()
            guard envelope.pending == nil else { throw SettlementFailure.notAccepted }
            envelope.pending = attempt
            try writeConfirmed(envelope) // Confirm the barrier before any SDK I/O.
        }
    }

    /// Call only after the actual SDK task has exited, never on cancellation alone.
    func abandon(_ attempt: UUID) throws {
        try Self.transactionLock.withLock {
            var envelope = try load()
            guard envelope.pending == attempt else { return }
            envelope.pending = nil
            try writeConfirmed(envelope)
        }
    }

    /// No suspension is allowed from fresh policy/ownership checks through adopt,
    /// this atomic acceptance point and recording the confirmed mutation.
    func accept(_ candidate: Session, attempt: UUID,
                evidence: MerianEnvironment.HistoryQualificationIdentityEvidence, at now: Date) throws {
        try Self.transactionLock.withLock {
            let before = try load()
            guard before.pending == attempt,
                  evidence.isBound(to: scope, at: now),
                  evidence.permitsInstalledAccount(candidate.user.id, isAnonymous: candidate.user.isAnonymous, at: now) else {
                throw SettlementFailure.notAccepted
            }
            let bytes = try JSONEncoder().encode(candidate)
            let accepted = Envelope(approved: bytes, receipt: Receipt(attempt: attempt,
                acceptedBytes: bytes, digest: Self.digest(bytes), evidence: evidence, acceptedAt: now))
            do { try writeConfirmed(accepted) } catch {
                // A thrown write is not proof of noncommit. The exact accepted
                // receipt, not account equality, resolves a lost acknowledgement.
                guard let actual = try? load() else { throw SettlementFailure.unresolved }
                if actual.pending == nil, actual.receipt?.attempt == attempt,
                   actual.receipt?.digest == Self.digest(bytes), actual.approved == bytes { return }
                if actual.pending == attempt, actual.approved == before.approved { throw SettlementFailure.notAccepted }
                throw SettlementFailure.unresolved
            }
        }
    }

    private func load() throws -> Envelope {
        guard let data = try storage.retrieve(key: Self.sessionKey) else { return Envelope() }
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data) {
            guard envelope.version == 1 else { throw SettlementFailure.unresolved }
            if let approved = envelope.approved { _ = try session(approved) }
            if let receipt = envelope.receipt {
                let original = try session(receipt.acceptedBytes)
                guard receipt.digest == Self.digest(receipt.acceptedBytes),
                      receipt.evidence.isBound(to: scope, at: receipt.acceptedAt),
                      receipt.evidence.permitsInstalledAccount(original.user.id, isAnonymous: original.user.isAnonymous, at: receipt.acceptedAt),
                      let approved = envelope.approved, try session(approved).user.id == original.user.id else {
                    throw SettlementFailure.unresolved
                }
            }
            return envelope
        }
        _ = try session(data) // Preserve existing approved raw SDK sessions.
        return Envelope(approved: data)
    }

    private func writeConfirmed(_ envelope: Envelope) throws {
        let data = try JSONEncoder().encode(envelope)
        do { try storage.store(key: Self.sessionKey, value: data) } catch { /* Read back exact bytes. */ }
        guard try storage.retrieve(key: Self.sessionKey) == data else { throw SettlementFailure.unresolved }
    }

    private func session(_ data: Data) throws -> Session {
        guard let value = try? JSONDecoder().decode(Session.self, from: data),
              !value.user.isAnonymous, scope.permits(accountID: value.user.id) else {
            throw MerianEnvironment.HistoryQualificationFailure.accounts
        }
        return value
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// The pinned SDK writes with SecItemAdd/Update (never delete-then-add). Normalize
/// only errSecItemNotFound on reads; locked/unreadable Keychain remains a failure.
private struct QualificationKeychainStorage: AuthLocalStorage {
    private let backing = KeychainLocalStorage(service: MerianEnvironment.HistoryQualificationScope.authNamespace)
    func store(key: String, value: Data) throws { try backing.store(key: key, value: value) }
    func remove(key: String) throws { if try retrieve(key: key) != nil { try backing.remove(key: key) } }
    func retrieve(key: String) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: MerianEnvironment.HistoryQualificationScope.authNamespace,
            kSecAttrAccount as String: key, kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw QualificationAuthStorage.SettlementFailure.unresolved }
        return data
    }
}

#if DEBUG
/// Test clients must neither restore nor overwrite a simulator's saved session.
/// Each client owns its storage; explicitly installed test sessions still work.
private struct ProcessLocalAuthStorage: AuthLocalStorage {
    private let values = OSAllocatedUnfairLock(initialState: [String: Data]())

    func store(key: String, value: Data) throws {
        values.withLock { $0[key] = value }
    }

    func retrieve(key: String) throws -> Data? {
        values.withLock { $0[key] }
    }

    func remove(key: String) throws {
        values.withLock { _ = $0.removeValue(forKey: key) }
    }
}
#endif
