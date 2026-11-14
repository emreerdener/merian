import Foundation

/// Immutable disposal evidence only. The old request epoch is bound through its
/// fingerprint; the current process/fence epoch is never persisted here.
struct SharedMediaNativePendingClosure: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case absent, partial, final }
    let version: Int
    let fingerprint: String
    let parent: String?
    let namespace: String
    let kind: Kind
    let file: String?

    func validate(request: SharedMediaAcquisitionIntent) throws {
        guard version == 1, fingerprint == (try request.fingerprint()) else { throw SharedMediaStorageFailure.conflict }
        try Self.directory(namespace)
        if let parent { try Self.directory(parent) }
        if kind == .absent {
            guard file == nil else { throw SharedMediaStorageFailure.conflict }
        } else {
            guard parent != nil, let file else { throw SharedMediaStorageFailure.conflict }
            let parts = file.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 7, let device = Int64(parts[0]), device >= 0, String(device) == parts[0],
                  let inode = UInt64(parts[1]), String(inode) == parts[1],
                  let bytes = Int64(parts[2]), bytes >= 0, bytes <= request.maximumBytes, String(bytes) == parts[2],
                  kind == .partial || bytes > 0 else { throw SharedMediaStorageFailure.conflict }
            for index in [3, 5] {
                guard let seconds = Int64(parts[index]), String(seconds) == parts[index],
                      let nanos = Int64(parts[index + 1]), (0..<1_000_000_000).contains(nanos), String(nanos) == parts[index + 1] else {
                    throw SharedMediaStorageFailure.conflict
                }
            }
        }
    }
    func encoded(request: SharedMediaAcquisitionIntent) throws -> String {
        try validate(request: request)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(self)
        guard bytes.count <= 512, let value = String(data: bytes, encoding: .utf8) else { throw SharedMediaStorageFailure.conflict }
        return value
    }
    static func decode(_ value: String, request: SharedMediaAcquisitionIntent) throws -> Self {
        guard value.utf8.count <= 512 else { throw SharedMediaStorageFailure.conflict }
        let result = try JSONDecoder().decode(Self.self, from: Data(value.utf8))
        guard try result.encoded(request: request) == value else { throw SharedMediaStorageFailure.conflict }
        return result
    }
    private static func directory(_ value: String) throws {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, let device = Int64(parts[0]), device >= 0, String(device) == parts[0],
              let inode = UInt64(parts[1]), String(inode) == parts[1] else { throw SharedMediaStorageFailure.conflict }
    }
}

struct SharedMediaNativePendingState: Equatable, Sendable {
    let request: SharedMediaAcquisitionIntent
    let receiptPhase: String, receiptRevision: Int64
    let inventoryRevision: Int64, packageRevision: Int64, membershipRevision: Int64
    let membershipBytes: Data, envelope: Data
    let allocatedBytes: Int64, phase: String
    let closure: SharedMediaNativePendingClosure?
}
