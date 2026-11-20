import Foundation
import Testing
@testable import Merian

struct SharedMediaNativeRetirementIdentityTests {
    private let proof = SharedMediaPhotoRetirementIdentity(version: 1,
        file: "1:2:17:3:4:5:6", parent: "1:7", namespace: "1:8")

    private func value(_ proof: SharedMediaPhotoRetirementIdentity) throws -> SharedMediaNativeRetirementIdentity {
        try .init(retirementID: UUID(), assetID: UUID(), assetGeneration: UUID(), inventoryID: UUID(),
            inventoryGeneration: UUID(), ownerID: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!, proof: proof)
    }

    @Test func canonicalRoundTripBindsEveryIdentityAndKeepsV1Separate() throws {
        let original = try value(proof), encoded = try original.encoded()
        #expect(try SharedMediaNativeRetirementIdentity.decode(encoded) == original)
        #expect(throws: (any Error).self) { try SharedMediaPhotoRetirementIdentity.decode(encoded) }
        #expect(throws: (any Error).self) { try SharedMediaNativeRetirementIdentity.decode(proof.encoded()) }
        #expect(try SharedMediaPhotoRetirementIdentity.decode(proof.encoded()) == proof)
        #expect(SharedMediaNativeRetirementIdentity.allocationState != "p1Retiring")
        for id in [original.retirementID, original.assetID, original.assetGeneration,
                   original.inventoryID, original.inventoryGeneration, original.ownerID] {
            let replaced = encoded.replacingOccurrences(of: id.uuidString.lowercased(), with: UUID().uuidString.lowercased())
            #expect(try SharedMediaNativeRetirementIdentity.decode(replaced) != original)
        }
    }

    @Test func maximumDescriptorValuesFitExistingCap() throws {
        let directory = "\(Int32.min):\(UInt64.max)"
        let largest = SharedMediaPhotoRetirementIdentity(version: 1,
            file: "\(directory):\(PhotoPreparationPolicy.original):\(Int64.min):999999999:\(Int64.min):999999999",
            parent: directory, namespace: directory)
        let original = try value(largest), encoded = try original.encoded()
        #expect(encoded.utf8.count <= 480)
        #expect(try SharedMediaNativeRetirementIdentity.decode(encoded) == original)
    }

    @Test func rejectsNoncanonicalAndUnknownEncoding() throws {
        let original = try value(proof), encoded = try original.encoded()
        let variants = [
            " " + encoded, encoded + " ",
            encoded.replacingOccurrences(of: "\"v\":2", with: "\"v\":1"),
            encoded.replacingOccurrences(of: "\"v\":2", with: "\"v\":2.0"),
            encoded.replacingOccurrences(of: "\"v\":2", with: "\"v\":2,\"v\":2"),
            encoded.replacingOccurrences(of: "\"v\":2", with: "\"v\":2,\"x\":0"),
            encoded.replacingOccurrences(of: original.ownerID.uuidString.lowercased(), with: original.ownerID.uuidString.uppercased()),
            encoded.replacingOccurrences(of: "\"v\":2", with: "\"v\":null"),
            String(repeating: "x", count: 513)
        ]
        for variant in variants {
            #expect(throws: (any Error).self) { try SharedMediaNativeRetirementIdentity.decode(variant) }
        }
    }

    @Test(arguments: ["1:2:0:3:4:5:6", "1:2:33554433:3:4:5:6", "1:2:17:3:1000000000:5:6",
        "1:2:17:3:4:5:-1", "2147483648:2:17:3:4:5:6", "1:18446744073709551616:17:3:4:5:6",
        "1:2:17:9223372036854775808:4:5:6", "01:2:17:3:4:5:6", "1:+2:17:3:4:5:6",
        "1:2:017:3:4:5:6", "1:2:17:-0:4:5:6", "1:2:17:3:4:5:", "1:2:17:3:4:5:6:7"])
    func rejectsMalformedDescriptor(_ file: String) throws {
        #expect(throws: (any Error).self) {
            try value(.init(version: 1, file: file, parent: proof.parent, namespace: proof.namespace))
        }
    }

    @Test(arguments: ["", "1", "1:2:3", "1:-1", "+1:2", "1:02", "1:2/other", "1:2\n"])
    func rejectsMalformedDirectory(_ directory: String) throws {
        for candidate in [SharedMediaPhotoRetirementIdentity(version: 1, file: proof.file, parent: directory, namespace: proof.namespace),
                          .init(version: 1, file: proof.file, parent: proof.parent, namespace: directory)] {
            #expect(throws: (any Error).self) { try value(candidate) }
        }
    }
}
