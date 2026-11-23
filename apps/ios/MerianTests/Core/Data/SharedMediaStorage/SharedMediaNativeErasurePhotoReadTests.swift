import CryptoKit
import Darwin
import Foundation
@testable import Merian
import Testing
import UIKit

@Suite(.serialized)
@MainActor
struct NativeErasurePhotoReadTests {
    typealias Reader = SharedMediaNativeErasurePhotoRead

    @Test func originalChecksDigestSiblingAndExactRetirementParent() throws {
        let fixture = try Fixture(); defer { fixture.close() }
        try fixture.bytes.write(to: fixture.final)
        let saved = try fixture.proof()
        let request = Reader.Request.original(fixture.file, saved, retiring: false)
        let first = try fixture.inspect(request)
        #expect(first.final == saved.file)
        #expect(first.entries(token: fixture.file.token).map(\.kind) == [.file, .absent])
        try Data().write(to: fixture.partial)
        #expect(throws: (any Error).self) { try fixture.inspect(request) }
        try FileManager.default.removeItem(at: fixture.partial)
        try FileManager.default.removeItem(at: fixture.final)
        #expect(throws: (any Error).self) { try fixture.inspect(request) }
        let retiring = Reader.Request.original(fixture.file, saved, retiring: true)
        #expect(try fixture.inspect(retiring).final == nil)
        try FileManager.default.removeItem(at: fixture.package)
        #expect(throws: (any Error).self) { try fixture.inspect(retiring) }
    }

    @Test func originalRejectsCorrectDescriptorWithWrongDigest() throws {
        let fixture = try Fixture(); defer { fixture.close() }
        try fixture.bytes.write(to: fixture.final)
        let saved = try fixture.proof(), file = fixture.file
        let wrong = PhotoPreparationFile(assetID: file.assetID, generation: file.generation,
            token: file.token, byteCount: file.byteCount, sha256: String(repeating: "0", count: 64), contentType: file.contentType)
        #expect(throws: (any Error).self) { try fixture.inspect(.original(wrong, saved, retiring: false)) }
    }

    @Test func pendingRequiresClosedEvidenceAndNeverAdoptsReplacement() throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let request = fixture.acquisition
        #expect(try fixture.inspect(.pending(request, nil)).final == nil)
        try Data([1, 2, 3]).write(to: fixture.partial)
        #expect(throws: (any Error).self) { try fixture.inspect(.pending(request, nil)) }
        let closure = SharedMediaNativePendingClosure(version: 1, fingerprint: try request.fingerprint(),
            parent: try Fixture.directory(fixture.package), namespace: try Fixture.directory(fixture.root),
            kind: .partial, file: try Fixture.identity(fixture.partial))
        #expect(try fixture.inspect(.pending(request, closure)).partial == closure.file)
        try FileManager.default.removeItem(at: fixture.partial)
        #expect(try fixture.inspect(.pending(request, closure)).partial == nil)
        try Data([4, 5, 6]).write(to: fixture.partial)
        #expect(throws: (any Error).self) { try fixture.inspect(.pending(request, closure)) }
    }

    @Test func interruptedOriginalObservationIsExactAndNeverPromotesMedia() throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let request = Reader.Request.interrupted(fixture.acquisition)
        try Data([1, 2, 3]).write(to: fixture.partial)
        let first = try fixture.inspect(request)
        #expect(first.partial == (try Fixture.identity(fixture.partial)))
        #expect(first.entries(token: fixture.file.token).filter { $0.kind == .file }.count == 1)
        try FileManager.default.removeItem(at: fixture.partial)
        try Data([4]).write(to: fixture.partial)
        #expect(try fixture.inspect(request) != first)
        try Data().write(to: fixture.final)
        #expect(throws: (any Error).self) { try fixture.inspect(request) }
    }

    @Test func derivativePreservesRenameBeforeCompletionAndRejectsSibling() throws {
        let fixture = try Fixture(); defer { fixture.close() }
        try fixture.bytes.write(to: fixture.partial)
        var value = stat(); #expect(lstat(fixture.partial.path, &value) == 0)
        let work = fixture.work(phase: "writing", device: Int64(value.st_dev), inode: Int64(value.st_ino))
        let request = Reader.Request.derivative(fixture.file, work)
        #expect(try fixture.inspect(request).partial != nil)
        try FileManager.default.moveItem(at: fixture.partial, to: fixture.final)
        #expect(try fixture.inspect(request).final != nil)
        try Data().write(to: fixture.partial)
        #expect(throws: (any Error).self) { try fixture.inspect(request) }
    }

    @Test func derivativePlannedReservedAndCompletedHaveDistinctRules() throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let planned = Reader.Request.derivative(fixture.file, fixture.work(phase: "planned"))
        let reserved = Reader.Request.derivative(fixture.file, fixture.work(phase: "reserved"))
        #expect(try fixture.inspect(planned).partial == nil)
        try Data().write(to: fixture.partial)
        #expect(throws: (any Error).self) { try fixture.inspect(planned) }
        #expect(try fixture.inspect(reserved).partial != nil)
        try Data([1]).write(to: fixture.partial)
        #expect(throws: (any Error).self) { try fixture.inspect(reserved) }
        try FileManager.default.removeItem(at: fixture.partial)
        try fixture.bytes.write(to: fixture.final)
        var value = stat(); #expect(lstat(fixture.final.path, &value) == 0)
        let saved = try Fixture.identity(fixture.final)
        let completed = Reader.Request.derivative(fixture.file, fixture.work(phase: "completed",
            device: Int64(value.st_dev), inode: Int64(value.st_ino), final: saved))
        #expect(try fixture.inspect(completed).final == saved)
        try FileManager.default.removeItem(at: fixture.final)
        #expect(throws: (any Error).self) { try fixture.inspect(completed) }
    }

    @Test(arguments: ["symlink", "hardlink", "foreign", "replacement", "revoke"])
    func rejectsPathAndScopeChanges(change: String) throws {
        let fixture = try Fixture(); defer { fixture.close() }
        try fixture.bytes.write(to: fixture.final)
        let request = Reader.Request.original(fixture.file, try fixture.proof(), retiring: false)
        if change == "symlink" {
            try FileManager.default.moveItem(at: fixture.final, to: fixture.root.appendingPathComponent("outside"))
            try FileManager.default.createSymbolicLink(atPath: fixture.final.path, withDestinationPath: fixture.root.appendingPathComponent("outside").path)
        } else if change == "hardlink" {
            try FileManager.default.linkItem(at: fixture.final, to: fixture.root.appendingPathComponent("outside"))
        }
        var calls = 0
        #expect(throws: (any Error).self) {
            try Reader.inspect(request, namespace: fixture.descriptor, ownerID: change == "foreign" ? UUID() : fixture.ownerID) {
                calls += 1
                if change == "revoke", calls >= 2 { throw SharedMediaStorageFailure.closed }
                if change == "replacement", calls == 2 {
                    try FileManager.default.moveItem(at: fixture.package, to: fixture.root.appendingPathComponent("old"))
                    try FileManager.default.createDirectory(at: fixture.package, withIntermediateDirectories: true)
                }
            }
        }
    }

    @MainActor private struct Fixture {
        let root: URL, package: URL, final: URL, partial: URL
        let descriptor: Int32
        let ownerID = UUID(), packageID = UUID(), assetID = UUID(), generation = UUID()
        let bytes: Data
        var file: PhotoPreparationFile {
            .init(assetID: assetID, generation: generation,
                token: [ownerID, packageID, assetID].map { $0.uuidString.lowercased() }.joined(separator: "/"),
                byteCount: Int64(bytes.count), sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), contentType: "public.png")
        }
        var acquisition: SharedMediaAcquisitionIntent {
            .init(operationID: UUID(), inventoryID: UUID(), inventoryGeneration: UUID(), ownerID: ownerID,
                expectedInventoryRevision: 0, packageID: packageID, draftGeneration: UUID(), packageExpectation: .absent,
                assetID: assetID, assetGeneration: generation, referenceID: UUID(), ordinal: 0, kind: .camera,
                writerEpoch: UUID(), maximumBytes: PhotoPreparationPolicy.original)
        }
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("erasure-photo-" + UUID().uuidString)
            package = root.appendingPathComponent(ownerID.uuidString.lowercased()).appendingPathComponent(packageID.uuidString.lowercased())
            final = package.appendingPathComponent(assetID.uuidString.lowercased()); partial = final.appendingPathExtension("partial")
            bytes = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
                UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            }
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            descriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { throw SharedMediaStorageFailure.unavailable }
        }
        func close() { Darwin.close(descriptor); try? FileManager.default.removeItem(at: root) }
        func inspect(_ request: Reader.Request) throws -> Reader.Observation {
            try Reader.inspect(request, namespace: descriptor, ownerID: ownerID, checkpoint: {})
        }
        func proof() throws -> SharedMediaPhotoRetirementIdentity {
            try .init(version: 1, file: Self.identity(final), parent: Self.directory(package), namespace: Self.directory(root))
        }
        func work(phase: String, device: Int64? = nil, inode: Int64? = nil, final: String? = nil) -> SharedMediaNativePairFileState.Work {
            .init(id: UUID(), writerEpoch: UUID(), phase: phase, writerState: phase == "completed" ? "closed" : "open",
                device: device, inode: inode, finalIdentity: final, retirementID: nil, retirementPartial: nil,
                retirementFinal: nil, retirementParent: nil, retirementNamespace: nil, closure: nil)
        }
        static func directory(_ url: URL) throws -> String {
            var value = stat(); guard lstat(url.path, &value) == 0 else { throw SharedMediaStorageFailure.unavailable }
            return "\(value.st_dev):\(value.st_ino)"
        }
        static func identity(_ url: URL) throws -> String {
            var value = stat(); guard lstat(url.path, &value) == 0 else { throw SharedMediaStorageFailure.unavailable }
            return "\(value.st_dev):\(value.st_ino):\(value.st_size):\(value.st_mtimespec.tv_sec):\(value.st_mtimespec.tv_nsec):\(value.st_ctimespec.tv_sec):\(value.st_ctimespec.tv_nsec)"
        }
    }
}
