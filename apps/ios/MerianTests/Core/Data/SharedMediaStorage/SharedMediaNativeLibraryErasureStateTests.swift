import Foundation
@testable import Merian
import Testing

@MainActor
struct NativeLibraryErasureStateTests {
    private func profile() -> SharedMediaNativeAppProfile {
        .init(ownerID: UUID(), inventoryID: UUID(), generation: UUID(), storeIdentity: UUID().uuidString,
            physicalBinding: String(repeating: "a", count: 64), receiptDigest: String(repeating: "b", count: 64),
            physicalBindingFormat: .physicalRootsV1)
    }

    private func row(_ profile: SharedMediaNativeAppProfile) throws -> SharedMediaInventoryRecord {
        .init(id: profile.inventoryID, rootIdentity: try profile.rootIdentity, storeIdentity: profile.storeIdentity,
            generation: profile.generation, revision: 7, modeRaw: SharedMediaNativeAppProfile.mode,
            phaseRaw: SharedMediaNativeAppProfile.phase, cursor: "")
    }

    @Test func erasurePhasesPreserveIdentityAndNeverAuthorizeNormalOpening() throws {
        let profile = profile(), row = try row(profile)
        #expect(try SharedMediaNativeAppEligibility.profile(row) == profile)
        let intent = try SharedMediaNativeLibraryErasureState.intent(id: UUID(), profile: profile,
            manifestSHA256: String(repeating: "c", count: 64), sourceRevision: row.revision)
        let retiring = try intent.retiring(), complete = try retiring.completed()
        for state in [intent, retiring, complete, try complete.cleared()] {
            row.cursor = try state.encoded(); row.phaseRaw = state.phase; row.revision = state.revision
            #expect(try SharedMediaNativeLibraryErasureState.read(row) == state)
            #expect(try SharedMediaNativeAppEligibility.profileAssertion(row) == profile)
            #expect(throws: (any Error).self) { try SharedMediaNativeAppEligibility.profile(row) }
            #expect(throws: (any Error).self) { try SharedMediaPurgeState.read(row) }
            #expect(row.modeRaw == SharedMediaNativeAppProfile.mode)
        }
    }

    @Test(arguments: ["mode", "phase", "revision", "generation", "profile", "noncanonical"])
    func mismatchedStateCannotBeRecovered(change: String) throws {
        let profile = profile(), row = try row(profile)
        let intent = try SharedMediaNativeLibraryErasureState.intent(id: UUID(), profile: profile,
            manifestSHA256: String(repeating: "c", count: 64), sourceRevision: row.revision)
        row.cursor = try intent.encoded(); row.phaseRaw = intent.phase; row.revision = intent.revision
        switch change {
        case "mode": row.modeRaw = SharedMediaStorageMode.p1InboxQualification.rawValue
        case "phase": row.phaseRaw = SharedMediaNativeAppProfile.phase
        case "revision": row.revision += 1
        case "generation": row.generation = UUID()
        case "profile": row.rootIdentity = try self.profile().rootIdentity
        default: row.cursor += " "
        }
        #expect(throws: (any Error).self) { try SharedMediaNativeLibraryErasureState.read(row) }
    }

    @Test func incompleteManifestCannotSkipToPhysicalCompletion() throws {
        let intent = try SharedMediaNativeLibraryErasureState.intent(id: UUID(), profile: profile(),
            manifestSHA256: String(repeating: "c", count: 64), sourceRevision: 0)
        #expect(throws: (any Error).self) { try intent.completed() }
        #expect(throws: (any Error).self) { try intent.cleared() }
        let retiring = try intent.retiring()
        #expect(throws: (any Error).self) { try retiring.retiring() }
        #expect(throws: (any Error).self) { try retiring.cleared() }
    }

    @Test func revisionOverflowAndInvalidManifestAreRejectedBeforeEncoding() throws {
        let profile = profile()
        for revision in [-1, Int64.max - 3, Int64.max - 2, Int64.max - 1, Int64.max] {
            #expect(throws: (any Error).self) {
                try SharedMediaNativeLibraryErasureState.intent(id: UUID(), profile: profile,
                    manifestSHA256: String(repeating: "c", count: 64), sourceRevision: revision)
            }
        }
        #expect(throws: (any Error).self) {
            try SharedMediaNativeLibraryErasureState.intent(id: UUID(), profile: profile,
                manifestSHA256: "not-a-manifest-digest", sourceRevision: 0)
        }
    }
}
