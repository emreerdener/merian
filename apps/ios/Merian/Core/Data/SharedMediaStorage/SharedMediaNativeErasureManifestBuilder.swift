import Foundation
import SwiftData

/// Builds deletion evidence while the accepted cleanup owner holds every
/// source namespace. The result retains only the parent fence, not child locks;
/// physical replay can therefore acquire those children without a lock gap in
/// the outer store/account authority. No rows or files are mutated here.
@MainActor
enum SharedMediaNativeErasureManifestBuilder {
    struct Candidate {
        let profile: SharedMediaNativeAppProfile
        let header: SharedMediaNativeErasureHeader
        let spool: SharedMediaNativeErasureManifestSpool
    }

    static func build(container: ModelContainer, parent: SharedMediaNativeErasureParent,
                      operationID: UUID, resuming: SharedMediaNativeErasureHeader? = nil) async throws -> Candidate {
        let sources = try parent.openSources(), profile = sources.profile
        let files = try sources.captureFiles()
        let scope = try SharedMediaNativeScopeIdentity(inventoryID: profile.inventoryID, generation: profile.generation,
            ownerID: profile.ownerID, storeIdentity: profile.storeIdentity, rootBinding: profile.rootIdentity)
        func readyHeader() throws -> SharedMediaNativeAppEligibility.Header {
            try sources.check()
            return try SharedMediaNativeAppEligibility.snapshot(context: ModelContext(container), scope: scope)
        }
        if let resuming {
            try sources.require(header: resuming)
            guard resuming.operationID == operationID else { throw SharedMediaStorageFailure.conflict }
            return try await SharedMediaNativeErasureAuditScope.withVerified(container: container, profile: profile,
                operationID: operationID, checkpoint: { try sources.require(header: resuming) }) { audit in
                    if let files {
                        _ = try await files.verifyForErasure(context: ModelContext(container), erasure: audit,
                            checkpoint: { try sources.require(header: resuming) })
                    }
                    let candidate = try await collect(container: container, parent: parent, sources: sources, files: files,
                        operationID: operationID, revision: resuming.sourceRevision, erasure: audit)
                    guard candidate.header == resuming else { throw SharedMediaStorageFailure.stale }
                    return candidate
                }
        }
        let before = try readyHeader()
        let graph = try SharedMediaNativeErasureGraph.snapshot(ModelContext(container), checkpoint: { try sources.check() })
        _ = try await SharedMediaNativeScopedAudit.runAppErasureInitial(container: container, profile: profile,
            files: files, header: readyHeader, betweenPages: { await Task.yield(); try sources.check() })
        let candidate = try await collect(container: container, parent: parent, sources: sources, files: files,
            operationID: operationID, revision: before.inventory.revision, erasure: nil)
        guard candidate.header.sourceTables == graph, try readyHeader() == before else { throw SharedMediaStorageFailure.stale }
        return candidate
    }

    private static func collect(container: ModelContainer, parent: SharedMediaNativeErasureParent,
                                sources: SharedMediaNativeErasureSources, files: SharedMediaCaptureArtifactFiles?,
                                operationID: UUID, revision: Int64,
                                erasure: SharedMediaNativeErasureAuditScope?) async throws -> Candidate {
        func check() throws {
            try sources.check(); try erasure?.requireCurrent(ModelContext(container))
        }
        try check()
        let graph = try SharedMediaNativeErasureGraph.snapshot(ModelContext(container), checkpoint: check)
        let spool = try SharedMediaNativeErasureManifestSpool(ownerID: sources.profile.ownerID,
            checkpoint: { try parent.check() })
        try sources.appendFixedEntries(to: spool)
        try sources.requireEmptyInbox()
        var describedFiles: Int64 = 0, physicalFiles: Int64 = 0
        try await SharedMediaNativeErasurePhotoProjection.visit(container: container, profile: sources.profile,
            checkpoint: check) { request in
                let value = try sources.inspectPhoto(request)
                // The canonical request/fingerprint lives in the frozen graph.
                // These exact leaf identities plus the walked ancestor entries
                // form its immutable cleanup closure, including interrupted
                // originals whose normal per-item closure was never saved.
                for entry in value.entries(token: request.token) {
                    try spool.append(entry)
                    if entry.kind == .file { describedFiles = try SharedMediaStoragePolicy.add(describedFiles, 1) }
                }
            }
        try await sources.visitPhotoEntries { entry in
            try check()
            if entry.kind == .directory {
                try spool.append(entry)
            } else if entry.kind == .file {
                physicalFiles = try SharedMediaStoragePolicy.add(physicalFiles, 1)
            } else { throw SharedMediaStorageFailure.conflict }
        }
        guard physicalFiles == describedFiles else { throw SharedMediaStorageFailure.conflict }
        if let files {
            func append(_ value: SharedMediaCaptureArtifactLedger.Snapshot) throws {
                for entry in try files.erasureEntries(value) { try spool.append(entry) }
            }
            if let erasure {
                _ = try SharedMediaCaptureArtifactStoreAudit.verifyForErasure(context: ModelContext(container), erasure: erasure,
                    rootBindingSHA256: files.rootBindingSHA256, checkpoint: check, inspectArtifact: append)
            } else {
                _ = try SharedMediaCaptureArtifactStoreAudit.verify(context: ModelContext(container), profile: sources.profile,
                    rootBindingSHA256: files.rootBindingSHA256, checkpoint: check, inspectArtifact: append)
            }
        } else {
            guard try ModelContext(container).fetchCount(FetchDescriptor<SharedMediaOrdinaryArtifactRecord>()) == 0 else {
                throw SharedMediaStorageFailure.conflict
            }
        }
        try await spool.seal()
        let chain = try await spool.visitPages(profile: sources.profile, operationID: operationID) { _ in }
        try check()
        guard try SharedMediaNativeErasureGraph.snapshot(ModelContext(container), checkpoint: check) == graph else {
            throw SharedMediaStorageFailure.stale
        }
        let header = try parent.makeHeader(profile: sources.profile, controlSHA256: sources.controlSHA256,
            sourceRevision: revision, sourceTables: graph, chain: chain)
        try sources.require(header: header)
        return .init(profile: sources.profile, header: header, spool: spool)
    }
}
