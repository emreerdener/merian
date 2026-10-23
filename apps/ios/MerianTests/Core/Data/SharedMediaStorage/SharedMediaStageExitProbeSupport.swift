import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import Merian

/// Opt-in simulator probe transport. Ordinary test runs never touch its files.
enum SharedMediaStageExitProbeSupport {
    enum Failure: Error { case invalid, consumed, unavailable }
    static let prefix = "MERIAN_STAGE_PROBE_"
    static let handshakeSelector = "merianTests/SharedMediaStageProbeTransportTests/testInvocationHandshake"
    static let childSelector = "merianTests/SharedMediaStageExitProbeTests/testNoSaveChildExit"
    static let readerSelector = "merianTests/SharedMediaStageExitProbeTests/testNoSaveReadback"

    struct Ticket: Codable, Equatable {
        let version: Int
        let nonce: UUID
        let candidate: String
        let appSHA256: String
        let testSHA256: String
    }

    struct Invocation {
        let ticket: Ticket
        let phase: String
        let root: URL
    }

    static func ticket(environment: [String: String], selector: String, phase: String) throws -> Ticket? {
        let keys = ["NONCE", "PHASE", "SELECTOR", "CANDIDATE", "APP_SHA256", "TEST_SHA256"]
        if keys.allSatisfy({ environment[prefix + $0] == nil }) { return nil }
        guard keys.allSatisfy({ environment[prefix + $0] != nil }),
              environment[prefix + "PHASE"] == phase,
              environment[prefix + "SELECTOR"] == selector,
              ["no-save-child": childSelector, "no-save-reader": readerSelector, "handshake": handshakeSelector][phase] == selector,
              let nonce = UUID(uuidString: environment[prefix + "NONCE"]!),
              nonce.uuidString.lowercased() == environment[prefix + "NONCE"] else { throw Failure.invalid }
        let hashes = ["CANDIDATE", "APP_SHA256", "TEST_SHA256"].map { environment[prefix + $0]! }
        guard hashes.allSatisfy({ $0.count == 64 && $0.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) }) else {
            throw Failure.invalid
        }
        return Ticket(version: 1, nonce: nonce, candidate: hashes[0], appSHA256: hashes[1], testSHA256: hashes[2])
    }

    static func invocation(selector: String, phase: String, testBundle: Bundle) throws -> Invocation {
        #if targetEnvironment(simulator)
        guard TestExecutionCoordinator.isRunningTests,
              let ticket = try ticket(environment: ProcessInfo.processInfo.environment, selector: selector, phase: phase) else {
            throw XCTSkip("Requires the exact reviewed simulator probe invocation.")
        }
        guard let app = Bundle.main.executableURL, let test = testBundle.executableURL,
              try digest(app) == ticket.appSHA256, try digest(test) == ticket.testSHA256 else { throw Failure.invalid }
        let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .resolvingSymlinksInPath().appendingPathComponent("merian-stage-exit-probes", isDirectory: true)
        let root = base.appendingPathComponent(ticket.nonce.uuidString.lowercased(), isDirectory: true)
        return Invocation(ticket: ticket, phase: phase, root: root)
        #else
        throw XCTSkip("Process-exit probes are simulator-only.")
        #endif
    }

    static func digest(_ url: URL) throws -> String {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.unavailable }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw Failure.invalid }
        var hash = SHA256(), buffer = [UInt8](repeating: 0, count: 1_048_576)
        while true {
            let capacity = buffer.count
            let count = Darwin.read(fd, &buffer, capacity)
            if count == 0 { break }
            if count < 0 { if errno == EINTR { continue }; throw Failure.unavailable }
            hash.update(data: Data(buffer.prefix(count)))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Only the script creates this nonce-specific root; no in-test repair.
    static func read<T: Codable>(_ type: T.Type, name: String, root: URL) throws -> T {
        try requireName(name)
        let parent = try directory(root)
        defer { close(parent) }
        let fd = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.unavailable }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
              info.st_size > 0, info.st_size <= 1_048_576 else { throw Failure.invalid }
        var bytes = [UInt8](repeating: 0, count: Int(info.st_size)), offset = 0
        while offset < bytes.count {
            let remaining = bytes.count - offset
            let count = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!.advanced(by: offset), remaining) }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw Failure.unavailable }
            offset += count
        }
        let data = Data(bytes), value = try JSONDecoder().decode(type, from: Data(bytes))
        guard try SharedMediaNativeDraftEnvelope.bytes(value) == data else { throw Failure.invalid }
        var after = stat()
        guard fstat(fd, &after) == 0, after.st_size == info.st_size, after.st_nlink == 1 else { throw Failure.invalid }
        return value
    }

    static func create<T: Encodable>(_ value: T, name: String, root: URL) throws {
        let bytes = try SharedMediaNativeDraftEnvelope.bytes(value)
        guard bytes.count <= 1_048_576 else { throw Failure.invalid }
        try requireName(name)
        let parent = try directory(root)
        defer { close(parent) }
        let fd = openat(parent, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw errno == EEXIST ? Failure.consumed : Failure.unavailable }
        defer { close(fd) }
        var offset = 0
        while offset < bytes.count {
            let count = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!.advanced(by: offset), bytes.count - offset) }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw Failure.unavailable }
            offset += count
        }
        guard fsync(fd) == 0, fsync(parent) == 0 else { throw Failure.unavailable }
    }

    private static func requireName(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else { throw Failure.invalid }
    }

    static func directory(_ url: URL) throws -> Int32 {
        guard url.isFileURL, !url.pathComponents.contains("..") else { throw Failure.invalid }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.unavailable }
        for component in url.standardizedFileURL.pathComponents.dropFirst() {
            let next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(fd)
            guard next >= 0 else { throw Failure.unavailable }
            fd = next
        }
        return fd
    }
}
