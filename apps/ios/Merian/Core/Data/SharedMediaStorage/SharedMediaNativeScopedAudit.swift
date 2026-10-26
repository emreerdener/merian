import Foundation
import SwiftData

/// Database facts only. Does not assert files exist or authorize their use.
struct SharedMediaNativeScopedSnapshot: Equatable, Sendable {
    let inventory: SharedMediaStorageSnapshot
    let pendingPackages: Int
    let consumers: Int64
    let receipts: Int64
    let allocations: Int64
}

/// Audits only inventory-anchored native records. Completely unanchored rows
/// cannot be distinguished from ordinary app data and are not adopted or repaired.
/// Contexts/models never survive a page await. Retained-library size is uncapped.
@MainActor
struct SharedMediaNativeScopedAudit {
    private typealias ProjectionMemo = SharedMediaNativeReleaseSurvivorProjection.Memo
    let container: ModelContainer
    private let appHeader: SharedMediaNativeAppEligibility.Header?
    private let format: SharedMediaNativeScopedFormat
    let scope: SharedMediaNativeScopeIdentity
    let expected: SharedMediaStorageSnapshot
    let check: () throws -> Void
    let betweenPages: () async throws -> Void
    #if DEBUG
    var inspectionTrace: SharedMediaNativeDebugHooks.InspectionTrace?
    #endif

    init(container: ModelContainer, scope: SharedMediaNativeScopeIdentity, expected: SharedMediaStorageSnapshot,
         check: @escaping () throws -> Void, betweenPages: @escaping () async throws -> Void) {
        self.init(container: container, scope: scope, expected: expected, format: .existingV1, check: check, betweenPages: betweenPages)
    }
    init(app container: ModelContainer, profile: SharedMediaNativeAppProfile, expected: SharedMediaStorageSnapshot,
         check: @escaping () throws -> Void, betweenPages: @escaping () async throws -> Void) throws {
        let scope = SharedMediaNativeScopeIdentity(inventoryID: profile.inventoryID, generation: profile.generation,
            ownerID: profile.ownerID, storeIdentity: profile.storeIdentity, rootBinding: try profile.rootIdentity)
        let context = ModelContext(container); context.autosaveEnabled = false
        let header = try SharedMediaNativeAppEligibility.snapshot(context: context, scope: scope)
        guard header.inventory == expected else { throw SharedMediaStorageFailure.conflict }
        self.init(container: container, scope: scope, expected: expected, format: .appV2,
            appHeader: header, check: check, betweenPages: betweenPages)
    }

    private init(container: ModelContainer, scope: SharedMediaNativeScopeIdentity, expected: SharedMediaStorageSnapshot,
                 format: SharedMediaNativeScopedFormat, appHeader: SharedMediaNativeAppEligibility.Header? = nil, check: @escaping () throws -> Void, betweenPages: @escaping () async throws -> Void) {
        self.container = container; self.scope = scope; self.expected = expected; self.format = format; self.appHeader = appHeader
        self.check = check; self.betweenPages = betweenPages
    }

    /// V1 uses the same read-fence discipline as the app audit. The caller
    /// retains capability/physical validation; this owner checks header stability.
    static func runExisting(container: ModelContainer, scope: SharedMediaNativeScopeIdentity,
                            header: @escaping () throws -> SharedMediaStorageSnapshot,
                            betweenPages: @escaping () async throws -> Void) async throws -> SharedMediaNativeScopedSnapshot {
        let expected = try header()
        let audit = Self(container: container, scope: scope, expected: expected, check: {
            guard try header() == expected else { throw SharedMediaStorageFailure.conflict }
        }, betweenPages: betweenPages)
        let result = try await audit.run()
        guard try header() == expected else { throw SharedMediaStorageFailure.conflict }
        return result
    }

    /// The audit owns header stability and diagnostic timing; the repository
    /// supplies only read validation and retains every grant and file fence.
    static func runApp(container: ModelContainer, profile: () throws -> SharedMediaNativeAppProfile,
                       header: @escaping () throws -> SharedMediaNativeAppEligibility.Header,
                       betweenPages: @escaping () async throws -> Void,
                       configure: (inout Self) -> Void) async throws -> SharedMediaNativeScopedSnapshot {
        let expected = try header(), profile = try profile()
        #if DEBUG
        var trace: SharedMediaNativeDebugHooks.InspectionTrace?
        #endif
        var audit = try Self(app: container, profile: profile, expected: expected.inventory, check: {
            #if DEBUG
            let started = trace == nil ? nil : ContinuousClock.now
            defer { if let started { trace?.checkpoint(started.duration(to: .now)) } }
            #endif
            guard try header() == expected else { throw SharedMediaStorageFailure.conflict }
        }, betweenPages: betweenPages)
        configure(&audit)
        #if DEBUG
        trace = audit.inspectionTrace
        #endif
        let result = try await audit.run()
        guard try header() == expected else { throw SharedMediaStorageFailure.conflict }
        return result
    }

    func run() async throws -> SharedMediaNativeScopedSnapshot {
        #if DEBUG
        inspectionTrace?.enter(.pending)
        #endif
        let count = try pending()
        let id = scope.inventoryID
        var futureReferences = Set<UUID>()
        #if DEBUG
        inspectionTrace?.enter(.receipts)
        #endif
        let receipts = try await page(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(
            predicate: #Predicate { $0.inventoryID == id }, sortBy: [SortDescriptor(\.id)])) { row, context, inventory, projectionMemo in
            guard row.ownerID == scope.ownerID, row.inventoryGeneration == scope.generation else { throw SharedMediaStorageFailure.conflict }
            switch try SharedMediaNativeAcquisitionGraph.scopedReceipt(row, inventory: inventory, context: context, format: format, checkpoint: check) {
            case .reserved(let request), .held(let request):
                _ = try package(request.packageID, context: context, inventory: inventory, projectionMemo: projectionMemo)
                guard futureReferences.insert(request.referenceID).inserted,
                      futureReferences.count <= PhotoPreparationPolicy.maximumPackages * 2 else { throw SharedMediaStorageFailure.conflict }
            case .completed: break // Current logical owners are reached through the physical allocation below.
            case .released: break // Stripped terminal rows do not prove any physical release.
            }
        }
        if format == .appV2 {
            try await receivingPages()
        }

        #if DEBUG
        inspectionTrace?.enter(.consumers)
        #endif
        let consumers = try await page(FetchDescriptor<SharedMediaConsumerRecord>(
            predicate: #Predicate { $0.inventoryID == id }, sortBy: [SortDescriptor(\.id)])) { row, context, inventory, projectionMemo in
            guard row.ownerID == scope.ownerID, row.inventoryGeneration == scope.generation else { throw SharedMediaStorageFailure.conflict }
            _ = try package(row.packageID, context: context, inventory: inventory, projectionMemo: projectionMemo)
            if let release = try release(row.packageID, context: context, inventory: inventory, projectionMemo: projectionMemo) {
                let origin = try SharedMediaNativeReleaseOrigin.read(release.release.progress.plan, in: context)
                guard origin.rows.consumer.persistentModelID == row.persistentModelID else {
                    throw SharedMediaStorageFailure.conflict
                }
            } else if row.kindRaw == "queue", let staged = try staged(row.packageID, context: context, inventory: inventory, projectionMemo: projectionMemo) {
                _ = try SharedMediaNativeConsumerGraph.validateStagedReceived(row, origin: staged.origin,
                    context: context, checkpoint: check)
            } else {
                _ = try SharedMediaNativeConsumerGraph.validateScoped(row, context: context, format: format, checkpoint: check)
            }
        }
        #if DEBUG
        inspectionTrace?.enter(.pairs)
        #endif
        _ = try await page(FetchDescriptor<SharedMediaDerivativePairRecord>(
            predicate: #Predicate { $0.inventoryID == id }, sortBy: [SortDescriptor(\.id)])) { row, context, inventory, projectionMemo in
            try pair(row, context: context, inventory: inventory, projectionMemo: projectionMemo)
        }
        #if DEBUG
        inspectionTrace?.enter(.allocations)
        #endif
        let allocations = try await page(FetchDescriptor<SharedMediaAllocationRecord>(
            predicate: #Predicate { $0.inventoryID == id }, sortBy: [SortDescriptor(\.id)])) { row, context, inventory, projectionMemo in
            guard row.accountID == scope.ownerID, row.namespaceRaw == SharedMediaPhotoLedger.namespace else { throw SharedMediaStorageFailure.conflict }
            try asset(row.id, context: context, inventory: inventory, projectionMemo: projectionMemo)
        }
        #if DEBUG
        inspectionTrace?.enter(.references)
        #endif
        _ = try await page(FetchDescriptor<SharedMediaAssetReferenceCountRecord>(
            predicate: #Predicate { $0.inventoryID == id }, sortBy: [SortDescriptor(\.id)])) { row, context, inventory, projectionMemo in
            guard row.ownerID == scope.ownerID, row.inventoryGeneration == scope.generation else { throw SharedMediaStorageFailure.conflict }
            try asset(row.id, context: context, inventory: inventory, projectionMemo: projectionMemo)
        }
        // Accountless inbox admission is not part of this exact native profile.
        #if DEBUG
        inspectionTrace?.enter(.inbox)
        #endif
        _ = try await page(FetchDescriptor<SharedMediaInboxSourceRecord>(
            predicate: #Predicate { $0.inventoryID == id }, sortBy: [SortDescriptor(\.id)])) { _, _, _, _ in
            throw SharedMediaStorageFailure.closed
        }
        #if DEBUG
        inspectionTrace?.enter(.finalHeader)
        #endif
        try check(); _ = try header(freshContext())
        return .init(inventory: expected, pendingPackages: count, consumers: consumers,
            receipts: receipts, allocations: allocations)
    }

    private func receivingPages() async throws {
        var offset = 0
        while true {
            try Task.checkCancellation(); try check()
            let count = try receivingPage(offset: offset)
            // The synchronous page releases its context/models/snapshots first.
            try await betweenPages(); try Task.checkCancellation(); try check()
            _ = try header(freshContext())
            if count < SharedMediaStoragePolicy.pageSize { return }
            let (next, overflow) = offset.addingReportingOverflow(count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }; offset = next
        }
    }

    private func receivingPage(offset: Int) throws -> Int {
        #if DEBUG
        inspectionTrace?.enter(.receivingRoots)
        #endif
        let projectionMemo = ProjectionMemo()
        let context = freshContext(), inventory = try header(context, projectionMemo: projectionMemo)
        let roots = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory,
            projectionMemo: projectionMemo, checkpoint: check)
        // No inventory predicate: foreign/orphan raw rows must fail closed.
        var query = FetchDescriptor<SharedMediaReceivingIntentRecord>(sortBy: [SortDescriptor(\.cursorKey)])
        query.fetchOffset = offset; query.fetchLimit = SharedMediaStoragePolicy.pageSize
        let rows = try context.fetch(query)
        var terminals: [SharedMediaNativeReceivingTerminal.Snapshot] = []
        #if DEBUG
        inspectionTrace?.enter(.receivingLeaves)
        #endif
        for row in rows {
            try Task.checkCancellation(); try check()
            if row.phaseRaw == "released" {
                terminals.append(try SharedMediaNativeReceivingTerminal.read(row, context: context,
                    inventory: inventory, checkpoint: check))
            } else {
                guard let witness = roots[row.id] else { throw SharedMediaStorageFailure.conflict }
                let saved: SharedMediaNativeReceivingIntentGraph.Row
                switch witness {
                case .generic(let value): saved = value.row
                case .releasing(let value): saved = value.release.slot
                case .staged(let value): saved = value.origin.row
                }
                guard saved == SharedMediaNativeReceivingIntentGraph.Row(row) else { throw SharedMediaStorageFailure.stale }
            }
        }
        #if DEBUG
        inspectionTrace?.enter(.receivingIdentities)
        #endif
        try SharedMediaNativeTerminalIdentity.auditPage(terminals, live: roots, context: context,
            expectedHeader: appHeader, checkpoint: check)
        // Fresh full pending-root/runway validation, not a header-only fence or
        // reuse of the page's projection memo, before any page suspension.
        #if DEBUG
        inspectionTrace?.enter(.receivingBoundary)
        #endif
        try check(); _ = try header(freshContext())
        return rows.count
    }

    private func pending() throws -> Int {
        try check()
        let projectionMemo = ProjectionMemo()
        let context = freshContext(), inventory = try header(context, projectionMemo: projectionMemo)
        let graph = try SharedMediaPendingGraph.deriveScoped(in: context, inventory: inventory, ownerID: scope.ownerID, format: format)
        guard graph.sources.isEmpty, graph.handoffs.isEmpty else { throw SharedMediaStorageFailure.closed }
        var active = 0, releasePairs = Set<UUID>()
        for row in graph.packages {
            try Task.checkCancellation(); try check()
            _ = try package(row.id, context: context, inventory: inventory, projectionMemo: projectionMemo)
            let envelope = try SharedMediaNativeDraftEnvelope.decode(row.supportingContextData)
            if let release = try release(row.id, context: context, inventory: inventory, projectionMemo: projectionMemo) {
                guard envelope.attempt == nil else { throw SharedMediaStorageFailure.conflict }
                for pair in release.pairs {
                    guard releasePairs.insert(try pair.intent().pairID).inserted else { throw SharedMediaStorageFailure.conflict }
                }
            }
            active += envelope.attempt == nil ? 0 : 1
        }
        active += graph.pairs.filter { $0.phaseRaw != "ready" && !releasePairs.contains($0.id) }.count
        guard active <= 1 else { throw SharedMediaStorageFailure.conflict }
        _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context, inventory: inventory, ownerID: scope.ownerID, format: format, projectionMemo: projectionMemo, checkpoint: check)
        try check(); _ = try header(context, projectionMemo: projectionMemo)
        return graph.packages.count
    }

    private func package(_ id: UUID, context: ModelContext, inventory: SharedMediaInventoryRecord, projectionMemo: ProjectionMemo) throws -> PhotoPreparationRecord {
        let row = try one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id }))
        guard row.ownerID == scope.ownerID else { throw SharedMediaStorageFailure.conflict }
        if let release = try release(id, context: context, inventory: inventory, projectionMemo: projectionMemo) {
            guard SharedMediaNativeAppMetadataFacts.Package(row) == release.release.state.package else {
                throw SharedMediaStorageFailure.stale
            }
            return row
        }
        if row.accountingTierRaw == "pending", let staged = try staged(id, context: context, inventory: inventory, projectionMemo: projectionMemo) {
            guard SharedMediaNativeAppMetadataFacts.Package(row) == staged.components.package else {
                throw SharedMediaStorageFailure.stale
            }
            return row // Typed origin already validates the frozen member and quartet.
        }
        let consumer = try SharedMediaConsumerLookup.one(context, packageID: id)
        if row.accountingTierRaw == "pending" {
            let member = try one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
            guard member.inventoryID == scope.inventoryID, member.inventoryGeneration == scope.generation,
                  member.ownerID == row.ownerID, member.draftGeneration == row.draftGeneration else { throw SharedMediaStorageFailure.conflict }
            try SharedMediaNativeAcquisitionGraph.scopedPendingPackage(row, inventory: inventory, context: context, format: format)
            if case .preparation(let envelope) = try SharedMediaNativeDraftEnvelope.decode(row.supportingContextData) {
                try SharedMediaNativePairPlanGraph.validate(envelope, package: row, inventory: inventory, context: context)
            }
            if let consumer {
                guard consumer.kindRaw == "queue" else { throw SharedMediaStorageFailure.conflict }
                _ = try SharedMediaNativeConsumerGraph.validateScoped(consumer, context: context, format: format, checkpoint: check)
            }
        } else {
            guard row.accountingTierRaw == "retained", let consumer, consumer.kindRaw != "queue" else { throw SharedMediaStorageFailure.conflict }
            _ = try SharedMediaNativeConsumerGraph.validateScoped(consumer, context: context, format: format, checkpoint: check)
        }
        if let consumer {
            guard consumer.inventoryID == inventory.id, consumer.inventoryGeneration == inventory.generation,
                  consumer.ownerID == scope.ownerID else { throw SharedMediaStorageFailure.conflict }
        }
        return row
    }

    private func pair(_ row: SharedMediaDerivativePairRecord, context: ModelContext, inventory: SharedMediaInventoryRecord, projectionMemo: ProjectionMemo) throws {
        guard row.inventoryID == scope.inventoryID, row.inventoryGeneration == scope.generation,
              row.ownerID == scope.ownerID else { throw SharedMediaStorageFailure.conflict }
        let owner = try package(row.packageID, context: context, inventory: inventory, projectionMemo: projectionMemo)
        if let release = try release(row.packageID, context: context, inventory: inventory, projectionMemo: projectionMemo) {
            let ids = try release.pairs.map { try $0.intent().pairID }
            guard ids.contains(row.id) else { throw SharedMediaStorageFailure.conflict }
            // The clean live audit fetched and validated this exact row in this
            // context, including its work, reference, lease and closure joins.
            let id = row.id
            let saved = try one(context, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == id }))
            guard saved.persistentModelID == row.persistentModelID else { throw SharedMediaStorageFailure.stale }
            return
        }
        guard case .preparation(let envelope) = try SharedMediaNativeDraftEnvelope.decode(owner.supportingContextData),
              try SharedMediaNativePairPlanGraph.select(envelope, pairID: row.id) != nil else { throw SharedMediaStorageFailure.conflict }
    }

    private func asset(_ id: UUID, context: ModelContext, inventory: SharedMediaInventoryRecord, projectionMemo: ProjectionMemo) throws {
        if let work = try SharedMediaNativePairFileGraph.nativeWork(assetID: id, context: context) {
            let pairID = work.pairID
            let row = try one(context, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == pairID }))
            try pair(row, context: context, inventory: inventory, projectionMemo: projectionMemo)
            return
        }
        let receipt = try one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == id }))
        guard receipt.inventoryID == scope.inventoryID, receipt.ownerID == scope.ownerID else { throw SharedMediaStorageFailure.conflict }
        let value = try SharedMediaNativeAcquisitionGraph.scopedReceipt(receipt, inventory: inventory, context: context, format: format, checkpoint: check)
        if case .completed = value {
            // The complete bidirectional audit validates every original edge.
            _ = try SharedMediaNativeOriginalAccounting.audit(assetID: id, inventoryID: inventory.id, context: context, checkpoint: check)
            var query = FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.assetID == id }, sortBy: [SortDescriptor(\.id)])
            query.fetchLimit = SharedMediaStoragePolicy.pageSize
            var offset = 0
            while true {
                try Task.checkCancellation(); try check(); query.fetchOffset = offset
                let refs = try context.fetch(query)
                for ref in refs {
                    try Task.checkCancellation(); try check()
                    _ = try package(ref.packageID, context: context, inventory: inventory, projectionMemo: projectionMemo)
                }
                if refs.count < SharedMediaStoragePolicy.pageSize { break }
                let (next, overflow) = offset.addingReportingOverflow(refs.count)
                guard !overflow else { throw SharedMediaStorageFailure.capacity }; offset = next
            }
        } else {
            switch value {
            case .reserved(let request), .held(let request): _ = try package(request.packageID, context: context, inventory: inventory, projectionMemo: projectionMemo)
            default: throw SharedMediaStorageFailure.conflict
            }
        }
    }

    /// Fresh-context classification, never a cached package-ID exemption.
    /// The complete live audit validates exact persisted rows before routing.
    private func release(_ packageID: UUID, context: ModelContext,
                         inventory: SharedMediaInventoryRecord, projectionMemo: ProjectionMemo) throws -> SharedMediaNativeReleaseMetadataSnapshot.Snapshot? {
        guard format == .appV2,
              let row = try SharedMediaNativeReceivingPhaseGraph.row(packageID, in: context),
              row.phaseRaw == "releasing" else { return nil }
        guard case .releasing(let snapshot) = try SharedMediaNativeReceivingCleanGraph.validate(
            .init(row), context: context, inventory: inventory, projectionMemo: projectionMemo, checkpoint: check) else {
            throw SharedMediaStorageFailure.conflict
        }
        return snapshot
    }

    private func staged(_ packageID: UUID, context: ModelContext,
                        inventory: SharedMediaInventoryRecord, projectionMemo: ProjectionMemo) throws -> SharedMediaNativeReceivedReleaseSnapshot.StagedSnapshot? {
        guard format == .appV2,
              let row = try SharedMediaNativeReceivingPhaseGraph.row(packageID, in: context),
              row.releaseStartData != nil || row.releaseStartSHA256 != nil else { return nil }
        guard case .staged(let snapshot) = try SharedMediaNativeReceivingCleanGraph.validate(
            .init(row), context: context, inventory: inventory, projectionMemo: projectionMemo, checkpoint: check) else {
            throw SharedMediaStorageFailure.conflict
        }
        return snapshot
    }

    private func freshContext() -> ModelContext {
        let context = ModelContext(container); context.autosaveEnabled = false; return context
    }
    private func header(_ context: ModelContext, projectionMemo: ProjectionMemo? = nil) throws -> SharedMediaInventoryRecord {
        guard !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let row = try format.header(context: context, scope: scope)
        // Bounded pending slots at every boundary; all raw slots receive a
        // separate paged reverse audit in run(). No retained-library count cap.
        if format == .appV2 {
            _ = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: row, projectionMemo: projectionMemo, checkpoint: check)
        } else {
            guard try context.fetchCount(FetchDescriptor<SharedMediaReceivingIntentRecord>()) == 0 else {
                throw SharedMediaStorageFailure.closed
            }
        }
        if let appHeader {
            guard try SharedMediaNativeAppEligibility.snapshot(context: context, scope: scope) == appHeader else { throw SharedMediaStorageFailure.conflict }
        }
        guard SharedMediaStorageSnapshot(generation: row.generation, revision: row.revision,
            phase: row.phaseRaw, cursor: row.cursor) == expected else { throw SharedMediaStorageFailure.conflict }
        return row
    }
    private func page<T: PersistentModel>(_ descriptor: FetchDescriptor<T>,
        body: (T, ModelContext, SharedMediaInventoryRecord, ProjectionMemo) throws -> Void) async throws -> Int64 {
        var offset = 0, total: Int64 = 0
        while true {
            try Task.checkCancellation(); try check()
            let count = try readPage(descriptor, offset: offset, body: body)
            total = try SharedMediaStoragePolicy.add(total, Int64(count))
            // readPage's context/models are released before this suspension.
            try await betweenPages(); try Task.checkCancellation(); try check()
            _ = try header(freshContext())
            if count < SharedMediaStoragePolicy.pageSize { return total }
            let (next, overflow) = offset.addingReportingOverflow(count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }; offset = next
        }
    }
    private func readPage<T: PersistentModel>(_ descriptor: FetchDescriptor<T>, offset: Int,
        body: (T, ModelContext, SharedMediaInventoryRecord, ProjectionMemo) throws -> Void) throws -> Int {
        let projectionMemo = ProjectionMemo()
        let context = freshContext(), inventory = try header(context, projectionMemo: projectionMemo)
        var query = descriptor; query.fetchLimit = SharedMediaStoragePolicy.pageSize; query.fetchOffset = offset
        let rows = try context.fetch(query)
        for row in rows { try Task.checkCancellation(); try check(); try body(row, context, inventory, projectionMemo) }
        try check(); _ = try header(context, projectionMemo: projectionMemo)
        return rows.count
    }
    private func one<T: PersistentModel>(_ context: ModelContext, _ query: FetchDescriptor<T>) throws -> T {
        try SharedMediaNativePairPlanGraph.one(context, query)
    }
}
