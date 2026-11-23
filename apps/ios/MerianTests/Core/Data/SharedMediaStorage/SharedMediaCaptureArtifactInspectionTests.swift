import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Capture artifact scoped accounting", .serialized)
@MainActor
struct SharedMediaCaptureArtifactInspectionTests {
    typealias Store = SharedMediaCaptureArtifactFilesTests.Store

    @Test(arguments: ["reserved", "writing", "ready"])
    func qualifiedCaptureJoinsTheWholeAppAuditWithoutDoubleCharging(_ phase: String) async throws {
        let store = try Store(fullSchema: true), profile = store.request.profile
        if phase == "writing" { _ = try store.begin(); try Data([7, 7]).write(to: store.partial) }
        if phase == "ready" { _ = try store.finish() }
        let observed = try await store.audit()
        let container = store.ledger.container
        let context = ModelContext(container); context.autosaveEnabled = false
        let identity = SharedMediaNativeScopeIdentity(inventoryID: profile.inventoryID, generation: profile.generation,
            ownerID: profile.ownerID, storeIdentity: profile.storeIdentity, rootBinding: try profile.rootIdentity)
        let header = { try SharedMediaNativeAppEligibility.snapshot(context: context, scope: identity) }
        await #expect(throws: (any Error).self) {
            _ = try await SharedMediaNativeScopedAudit.runAppAcceptedOrdinary(container: container,
                profile: { profile }, header: header, betweenPages: {}, configure: { _ in })
        }
        let result = try await SharedMediaNativeScopedAudit.runAppCapture(container: container, profile: profile,
            files: store.files, header: header, betweenPages: {}, configure: { _ in })
        #expect(result.allocations == 1 && result.pendingPackages == 0)
        var escapedCapture: SharedMediaCaptureArtifactInspection?, escapedOrdinary: SharedMediaOrdinaryInspection?
        try await SharedMediaCaptureArtifactInspection.withVerified(container: container, profile: profile,
            files: store.files, checkpoint: {}) { capture in
                escapedCapture = capture
                try await SharedMediaOrdinaryInspection.withVerifiedCapture(container: container, profile: profile,
                    capture: capture, checkpoint: {}) { ordinary in
                        escapedOrdinary = ordinary
                        let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context,
                            inventory: store.ledger.inventory, ownerID: profile.ownerID, format: .appV2, ordinary: ordinary)
                        var expected = SharedMediaStoragePolicy.Totals()
                        try expected.includePhotoPhysical(materialized: observed.ledger.materializedBytes + observed.ledger.metadataBytes,
                            reserved: observed.ledger.reservedBytes + observed.ledger.futureMetadataReservationBytes)
                        #expect(budget.totals == expected)
                    }
            }
        #expect(throws: SharedMediaStorageFailure.closed) { try escapedCapture?.requireCurrent(context) }
        #expect(throws: SharedMediaStorageFailure.closed) { try escapedOrdinary?.requireCurrent(context) }
    }

    @Test func ambiguousPartialCannotEnterTheReadScope() async throws {
        let store = try Store()
        try Data().write(to: store.partial)
        var entered = false
        await #expect(throws: SharedMediaStorageFailure.closed) {
            try await SharedMediaCaptureArtifactInspection.withVerified(container: store.ledger.container,
                profile: store.request.profile, files: store.files, checkpoint: {}) { _ in entered = true }
        }
        #expect(!entered && store.ledger.row.phaseRaw == "reserved")
        #expect(FileManager.default.fileExists(atPath: store.partial.path))
    }

    @Test func readFenceRemainsActiveAfterPageSuspension() async throws {
        let store = try Store(fullSchema: true), profile = store.request.profile
        let context = ModelContext(store.ledger.container); context.autosaveEnabled = false
        let scope = SharedMediaNativeScopeIdentity(inventoryID: profile.inventoryID, generation: profile.generation,
            ownerID: profile.ownerID, storeIdentity: profile.storeIdentity, rootBinding: try profile.rootIdentity)
        let header = { try SharedMediaNativeAppEligibility.snapshot(context: context, scope: scope) }
        var suspended = false, checkedAfterSuspension = false
        await #expect(throws: SharedMediaStorageFailure.stale) {
            _ = try await SharedMediaNativeScopedAudit.runAppCapture(container: store.ledger.container, profile: profile,
                files: store.files, header: header, readCheckpoint: {
                    if suspended { checkedAfterSuspension = true; throw SharedMediaStorageFailure.stale }
                    return try header()
                }, betweenPages: { suspended = true; await Task.yield() }, configure: { _ in })
        }
        #expect(suspended && checkedAfterSuspension)
    }

    @Test func expiredCaptureCannotQualifyAnOrdinaryOriginalRead() async throws {
        let store = try Store(), profile = store.request.profile
        var escaped: SharedMediaCaptureArtifactInspection?
        try await SharedMediaCaptureArtifactInspection.withVerified(container: store.ledger.container,
            profile: profile, files: store.files, checkpoint: {}) { escaped = $0 }
        #expect(throws: SharedMediaStorageFailure.closed) {
            _ = try SharedMediaNativeOriginalAccounting.auditAcceptedOrdinary(assetID: UUID(),
                inventoryID: profile.inventoryID, context: store.ledger.context, capture: escaped)
        }
    }

    @Test(arguments: ["account", "revision", "bytes", "foreignContainer"])
    func scopeRejectsChangesAcrossSuspensionAndInvalidatesOnFailure(_ mutation: String) async throws {
        let store = try Store(), other = try Store()
        _ = try store.finish()
        var currentAccount = true, escaped: SharedMediaCaptureArtifactInspection?
        await #expect(throws: (any Error).self) {
            try await SharedMediaCaptureArtifactInspection.withVerified(container: store.ledger.container,
                profile: store.request.profile, files: store.files, checkpoint: {
                    guard currentAccount else { throw SharedMediaStorageFailure.stale }
                }) { capture in
                    escaped = capture
                    await Task.yield()
                    switch mutation {
                    case "account": currentAccount = false
                    case "revision": store.ledger.inventory.revision += 1; try store.ledger.context.save()
                    case "bytes": try Data(repeating: 8, count: 48).write(to: store.final)
                    case "foreignContainer": try capture.requireCurrent(other.ledger.context)
                    default: Issue.record("Unknown mutation")
                    }
                }
        }
        #expect(throws: SharedMediaStorageFailure.closed) { try escaped?.requireCurrent(store.ledger.context) }
    }
}
