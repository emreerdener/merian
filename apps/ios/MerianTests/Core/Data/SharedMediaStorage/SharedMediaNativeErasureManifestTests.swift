import Foundation
@testable import Merian
import Testing

@MainActor
struct NativeErasureManifestTests {
    private func profile() -> SharedMediaNativeAppProfile {
        .init(ownerID: UUID(), inventoryID: UUID(), generation: UUID(), storeIdentity: UUID().uuidString,
            physicalBinding: String(repeating: "a", count: 64), receiptDigest: String(repeating: "b", count: 64))
    }

    @Test func streamingManifestRejectsMissingReorderedAndForeignPages() throws {
        typealias Manifest = SharedMediaNativeErasureManifest
        let profile = profile(), operation = UUID()
        let binding = try SharedMediaAcquisitionEncoding.digest(profile.binding)
        let first = try Manifest.Page(version: 1, operationID: operation, profileSHA256: binding,
            ordinal: 0, previousSHA256: nil,
            entries: [.init(namespace: .authority, token: ".", kind: .directory, identity: "1:2")]).encoded(profile: profile)
        let last = try Manifest.Page(version: 1, operationID: operation, profileSHA256: binding,
            ordinal: 1, previousSHA256: SharedMediaAcquisitionEncoding.digest(first),
            entries: [.init(namespace: .capture, token: ".", kind: .absent, identity: nil)]).encoded(profile: profile)
        var chain = Manifest.Chain(operationID: operation, profile: profile)
        #expect(throws: (any Error).self) { try chain.consume(last) }
        _ = try chain.consume(first)
        #expect(throws: (any Error).self) { try chain.consume(first) }
        #expect(throws: (any Error).self) {
            try chain.requireComplete(pages: 2, entries: 2, lastSHA256: SharedMediaAcquisitionEncoding.digest(last))
        }
        _ = try chain.consume(last)
        try chain.requireComplete(pages: 2, entries: 2, lastSHA256: SharedMediaAcquisitionEncoding.digest(last))
        var foreign = Manifest.Chain(operationID: UUID(), profile: profile)
        #expect(throws: (any Error).self) { try foreign.consume(first) }
        #expect(throws: (any Error).self) { try Manifest.Page.decode(first, profile: self.profile()) }
    }

    @Test func manifestCannotDescribeArbitraryPathsOrAdoptAbsentFiles() throws {
        typealias Manifest = SharedMediaNativeErasureManifest
        let owner = UUID(), item = UUID().uuidString.lowercased()
        for entry in [
            Manifest.Entry(namespace: .photo, token: "PhotoPreparation/../outside", kind: .file, identity: "1:2:3:4:5:6:7"),
            .init(namespace: .photo, token: "PhotoPreparation/\(UUID().uuidString.lowercased())/\(item)/\(item)", kind: .file, identity: "1:2:3:4:5:6:7"),
            .init(namespace: .capture, token: "CaptureArtifacts/\(item)", kind: .directory, identity: "1:2"),
            .init(namespace: .control, token: "library-erasure-v1.json", kind: .file, identity: "1:2:3:4:5:6:7"),
            .init(namespace: .inbox, token: "InboxSources/\(item)", kind: .absent, identity: "1:2:3:4:5:6:7")
        ] {
            #expect(throws: (any Error).self) { try entry.validate(ownerID: owner) }
        }
        try Manifest.Entry(namespace: .photo,
            token: "PhotoPreparation/\(owner.uuidString.lowercased())/\(item)/\(item).partial",
            kind: .file, identity: "1:2:0:4:5:6:7").validate(ownerID: owner)
    }

    @Test func descriptorGrammarPreservesDarwinDeviceAndInodeRanges() throws {
        let owner = UUID(), item = UUID().uuidString.lowercased()
        for namespace in [SharedMediaNativeErasureManifest.Namespace.inbox, .capture, .photo] {
            let base: String
            switch namespace {
            case .inbox: base = "InboxSources/" + item
            case .capture: base = "CaptureArtifacts/" + item
            default: base = "PhotoPreparation/" + owner.uuidString.lowercased() + "/" + item + "/" + item
            }
            for suffix in ["", ".partial"] {
                let token = base + suffix
                try SharedMediaNativeErasureManifest.Entry(namespace: namespace, token: token,
                    kind: .file, identity: "-1:18446744073709551615:0:-2:0:3:999999999").validate(ownerID: owner)
                for identity in ["2147483648:1:0:0:0:0:0", "1:01:0:0:0:0:0", "1:0:0:0:0:0:0",
                                 "1:2:-1:0:0:0:0", "1:2:0:0:1000000000:0:0", "1:2:0:0:0:0:-1"] {
                    #expect(throws: (any Error).self) {
                        try SharedMediaNativeErasureManifest.Entry(namespace: namespace, token: token,
                            kind: .file, identity: identity).validate(ownerID: owner)
                    }
                }
            }
        }
    }

    @Test func pageBoundAndDuplicateEntriesAreRejectedBeforeEncoding() throws {
        typealias Manifest = SharedMediaNativeErasureManifest
        let profile = profile(), operation = UUID()
        let entry = Manifest.Entry(namespace: .capture, token: ".", kind: .absent, identity: nil)
        for count in [0, 2, Manifest.pageSize + 1] {
            #expect(throws: (any Error).self) {
                try Manifest.Page(version: 1, operationID: operation,
                    profileSHA256: SharedMediaAcquisitionEncoding.digest(profile.binding), ordinal: 0,
                    previousSHA256: nil, entries: Array(repeating: entry, count: count)).encoded(profile: profile)
            }
        }
    }
}
