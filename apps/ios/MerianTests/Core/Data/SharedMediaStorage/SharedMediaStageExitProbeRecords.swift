import Darwin
import Foundation
import SwiftData
@testable import Merian

/// Only the explicitly armed simulator tests consume these bounded records.
@MainActor
enum SharedMediaStageExitProbeRecords {
    typealias Probe = SharedMediaStageExitProbeSupport
    typealias Locations = SharedMediaStageExitProbeLocation

    struct Process: Codable, Equatable {
        let ticket: Probe.Ticket
        let pid: Int32
        let processNonce: UUID
        let location: Locations.Location
    }
    struct Observer: Codable, Equatable {
        let process: Process
        let executable: String
        let startSeconds: UInt64
        let startMicroseconds: UInt64
    }
    struct Fixture: Codable, Equatable {
        let location: Locations.Location
        let storeRelative: String
        let controlRelative: String
        let physical: [String: Locations.Identity]
        let storeIdentity: String
        let fenceParent: String
        let fenceControl: String
        let inventoryID: UUID
        let packageID: UUID
        let ownerID: UUID
        let releaseID: UUID
        let state: SharedMediaStageExitProbeState.Snapshot
    }
    struct Boundary: Codable, Equatable {
        let observer: Observer
        let phase: String
        let intendedExit: Int
        let fixtureSHA256: String
    }
    struct Closure: Codable, Equatable {
        let boundary: Boundary
        let processTerminationObserved: Bool
        let pidAbsent: Bool
        let invocationEnded: Bool
        let outerExit: Int
        let numericHostStatusObserved: Bool
    }
    struct Presence: Codable, Equatable {
        let store: Bool
        let wal: Bool
        let shm: Bool
    }
    struct Readback: Codable, Equatable {
        let closure: Closure
        let location: Locations.Location
    }

    static func require(_ condition: Bool) throws {
        guard condition else { throw Probe.Failure.invalid }
    }

    /// Publication is a separate entry created only after the corresponding
    /// canonical record has been fully synchronized. Its contents confer no
    /// authority; the reader still validates that complete record and identity.
    static func observerPublished(root: URL) throws -> Bool {
        let fd = try Probe.directory(root)
        defer { close(fd) }
        var info = stat()
        if fstatat(fd, "observer-published.json", &info, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else { throw Probe.Failure.unavailable }
            return false
        }
        try require(info.st_mode & S_IFMT == S_IFREG && info.st_nlink == 1)
        return true
    }

    /// No-follow all path components before opening metadata or SwiftData.
    /// Only the recorded disposable test roots are allowed; no installed store.
    static func paths(_ fixture: Fixture, current: Locations.Location) throws -> (store: URL, control: URL) {
        try current.requireSamePhysicalRoot(as: fixture.location)
        let data = URL(fileURLWithPath: current.dataPath)
        let store = try Locations.resolve(fixture.storeRelative, below: data)
        let control = try Locations.resolve(fixture.controlRelative, below: data)
        try Locations.requireSameBindings(physical(store: store, control: control, data: data), fixture.physical)
        _ = try presence(store) // Missing store fails before constructor.
        return (store, control)
    }

    static func relative(_ url: URL, below data: URL) throws -> String {
        let prefix = data.path + "/"
        try require(url.path.hasPrefix(prefix))
        let relative = String(url.path.dropFirst(prefix.count))
        try require(try Locations.resolve(relative, below: data).path == url.path)
        return relative
    }

    static func physical(store: URL, control: URL, data: URL) throws -> [String: Locations.Identity] {
        let storeParts = try relative(store, below: data).split(separator: "/").map(String.init)
        let controlParts = try relative(control, below: data).split(separator: "/").map(String.init)
        try require(storeParts.count == 4 && storeParts[0] == "tmp" && storeParts[2] == "database" && storeParts[3] == "ledger.store")
        try require(controlParts.count == 4 && controlParts[0] == "Library" && controlParts[1] == "Application Support" && controlParts[3] == "control")
        for name in [storeParts[1], controlParts[2]] {
            let prefix = "native-app-metadata-"
            try require(name.hasPrefix(prefix))
            let suffix = String(name.dropFirst(prefix.count))
            try require(UUID(uuidString: suffix)?.uuidString == suffix)
        }
        return try ["store": Locations.identity(store, directory: false),
            "database": Locations.identity(store.deletingLastPathComponent(), directory: true),
            "storeRoot": Locations.identity(store.deletingLastPathComponent().deletingLastPathComponent(), directory: true),
            "control": Locations.identity(control, directory: true),
            "controlRoot": Locations.identity(control.deletingLastPathComponent(), directory: true)]
    }

    static func presence(_ store: URL) throws -> Presence {
        let parent = try Probe.directory(store.deletingLastPathComponent())
        defer { close(parent) }
        func exists(_ name: String) throws -> Bool {
            var info = stat()
            if fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) != 0 {
                guard errno == ENOENT else { throw Probe.Failure.unavailable }
                return false
            }
            try require(info.st_mode & S_IFMT == S_IFREG && info.st_nlink == 1)
            return true
        }
        let result = try Presence(store: exists(store.lastPathComponent), wal: exists(store.lastPathComponent + "-wal"),
            shm: exists(store.lastPathComponent + "-shm"))
        try require(result.store)
        return result
    }

    /// Read the named fence identity while the actual owner holds it; never
    /// drop/reacquire that owner's lock to manufacture an identity observation.
    static func binding(_ store: URL) throws -> SharedMediaStoreReadFence.Binding {
        let fd = try Probe.directory(store.deletingLastPathComponent())
        defer { close(fd) }
        var parent = stat(), file = stat()
        try require(fstat(fd, &parent) == 0)
        try require(fstatat(fd, SharedMediaStoreReadFence.name, &file, AT_SYMLINK_NOFOLLOW) == 0)
        try require(file.st_mode & S_IFMT == S_IFREG && file.st_nlink == 1 && file.st_size == 0)
        return .init(parent: "\(parent.st_dev):\(parent.st_ino)", control: "\(file.st_dev):\(file.st_ino)")
    }

    static func requireHeld(_ store: URL) throws {
        do {
            let unexpected = try SharedMediaStoreReadFence(store: store, access: .sharedWriter, requireExisting: true)
            withExtendedLifetime(unexpected) {}
        } catch SharedMediaStorageFailure.busy { return }
        throw Probe.Failure.invalid
    }
}
