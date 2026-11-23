import Foundation

/// The account lifetime owns this collector before the first disposable write.
/// Failure to qualify or remove a copy remains a cleanup liability.
@MainActor
final class CaptureDraftPresentationResources {
    let id = UUID()
    private let io: FileIOActor
    private var receipts: [String: LegacyMediaFileRetirement] = [:]
    private var unqualified: Set<String> = []
    private(set) var paths: Set<String> = []
    private var playback: [ObjectIdentifier: MediaPlaybackLifetime] = [:]
    private var isClosing = false
    private var readers: [UUID: CaptureInitialDraftWorkHost] = [:]

    init(io: FileIOActor = .shared) { self.io = io }

    /// Still-frame/video-editor decoding also borrows disposable paths even
    /// when no player is mounted. Account cleanup joins those readers too.
    func read<Value: Sendable>(_ operation: @escaping @MainActor () async throws -> Value) async throws -> Value {
        guard !isClosing else { throw SharedMediaStorageFailure.closed }
        let id = UUID(), reader = CaptureInitialDraftWorkHost()
        readers[id] = reader
        defer { readers[id] = nil }
        return try await reader.run(requireCurrent: { [self] in
            guard !isClosing else { throw SharedMediaStorageFailure.closed }
        }, operation: operation)
    }

    func retainPlayback(_ lifetime: MediaPlaybackLifetime) throws {
        guard !isClosing, !lifetime.isClosed else { throw SharedMediaStorageFailure.closed }
        playback[ObjectIdentifier(lifetime)] = lifetime
    }

    func releasePlayback(_ lifetime: MediaPlaybackLifetime) async {
        await lifetime.close()
        playback[ObjectIdentifier(lifetime)] = nil
    }

    func retainAll(_ paths: [String]) async throws {
        var complete = true
        for path in paths {
            do { try await retain(path) } catch { complete = false }
        }
        guard complete else { throw SharedMediaStorageFailure.unavailable }
    }

    func retain(_ path: String) async throws {
        guard !paths.contains(path) else { return }
        paths.insert(path); unqualified.insert(path)
        guard let receipt = await io.retirementForDisposableFile(at: path) else {
            throw SharedMediaStorageFailure.unavailable
        }
        receipts[path] = receipt; unqualified.remove(path)
    }

    @discardableResult
    func discard() async -> Bool {
        isClosing = true
        for reader in Array(readers.values) { _ = await reader.close() }
        for consumer in Array(playback.values) { await consumer.close() }
        playback.removeAll()
        let complete = await io.retireDisposableFiles(Array(receipts.values))
        return complete && unqualified.isEmpty
    }

    func discard(_ path: String) async -> Bool {
        guard let receipt = receipts[path], !unqualified.contains(path) else { return false }
        return await io.retireDisposableFiles([receipt])
    }
}
