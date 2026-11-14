import Darwin
import Foundation

/// Test-only physical continuity across simulator container pathname changes.
/// No stored path or SQLite UUID can substitute for these descriptor identities.
enum SharedMediaStageExitProbeLocation {
    typealias Probe = SharedMediaStageExitProbeSupport

    struct Identity: Codable, Equatable {
        let device: UInt64
        let inode: UInt64
        let kind: UInt32
        let links: UInt64

        func matchesPhysicalIdentity(_ other: Identity) -> Bool {
            guard device == other.device, inode == other.inode, kind == other.kind else { return false }
            if kind == UInt32(S_IFDIR) { return links > 0 && other.links > 0 }
            return kind == UInt32(S_IFREG) && links == 1 && other.links == 1
        }
    }

    static func requireSameBindings(_ actual: [String: Identity], _ expected: [String: Identity]) throws {
        guard Set(actual.keys) == Set(expected.keys), actual.allSatisfy({ key, value in
            expected[key].map { value.matchesPhysicalIdentity($0) } == true
        }) else { throw Probe.Failure.invalid }
    }

    struct Location: Codable, Equatable {
        let dataPath: String // Evidence only; never a reopened reader authority.
        let bundle: String
        let nonce: UUID
        let bindings: [String: Identity]

        func requireSamePhysicalRoot(as other: Location) throws {
            guard bundle == "app.merian.Merian", bundle == other.bundle, nonce == other.nonce,
                  Set(bindings.keys) == Set(SharedMediaStageExitProbeLocation.components(nonce)) else { throw Probe.Failure.invalid }
            try SharedMediaStageExitProbeLocation.requireSameBindings(bindings, other.bindings)
            for path in [dataPath, other.dataPath] {
                guard path.hasPrefix("/"), URL(fileURLWithPath: path).standardizedFileURL.path == path else {
                    throw Probe.Failure.invalid
                }
            }
        }
    }

    struct Anchor: Codable, Equatable {
        let ticket: Probe.Ticket
        let location: Location
    }

    static func components(_ nonce: UUID) -> [String] {
        ["", "Library", "Library/Caches", "Library/Caches/merian-stage-exit-probes",
         "Library/Caches/merian-stage-exit-probes/" + nonce.uuidString.lowercased()]
    }

    static func current(ticket: Probe.Ticket, probeRoot: URL) throws -> Location {
        let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false).standardizedFileURL
        let data = caches.deletingLastPathComponent().deletingLastPathComponent()
        guard caches.path == data.appendingPathComponent("Library/Caches").path,
              probeRoot.standardizedFileURL.path == data.appendingPathComponent(components(ticket.nonce).last!).path,
              Bundle.main.bundleIdentifier == "app.merian.Merian" else { throw Probe.Failure.invalid }
        return try capture(data: data, nonce: ticket.nonce)
    }

    static func capture(data: URL, nonce: UUID) throws -> Location {
        guard data.isFileURL, data.path == data.standardizedFileURL.path else { throw Probe.Failure.invalid }
        let pairs = try components(nonce).map { relative in
            (relative, try identity(relative.isEmpty ? data : resolve(relative, below: data), directory: true))
        }
        return Location(dataPath: data.path, bundle: "app.merian.Merian", nonce: nonce,
            bindings: Dictionary(uniqueKeysWithValues: pairs))
    }

    static func resolve(_ relative: String, below data: URL) throws -> URL {
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") }),
              !relative.hasPrefix("/"), data.isFileURL, data.path == data.standardizedFileURL.path else {
            throw Probe.Failure.invalid
        }
        return parts.reduce(data) { $0.appendingPathComponent(String($1)) }
    }

    static func identity(_ url: URL, directory: Bool) throws -> Identity {
        let fd: Int32
        if directory {
            fd = try Probe.directory(url)
        } else {
            let parent = try Probe.directory(url.deletingLastPathComponent())
            defer { close(parent) }
            fd = openat(parent, url.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw Probe.Failure.unavailable }
        }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG),
              info.st_nlink > 0, directory || info.st_nlink == 1 else { throw Probe.Failure.invalid }
        return Identity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino),
            kind: UInt32(info.st_mode & S_IFMT), links: UInt64(info.st_nlink))
    }
}
