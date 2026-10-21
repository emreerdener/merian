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
    let container: ModelContainer
    private let appHeader: SharedMediaNativeAppEligibility.Header?
    private let format: SharedMediaNativeScopedFormat
    let scope: SharedMediaNativeScopeIdentity
    let expected: SharedMediaStorageSnapshot
    let check: () throws -> Void
    let betweenPages: () async throws -> Void

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

    func run() async throws -> SharedMediaNativeScopedSnapshot {
        let count = try pending()
        let id = scope.inventoryID
        var futureReferences = Set<UUID>()
        let receipts = try await page(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(
            predicate: #Predicate { $0.inventoryID == id }, sortBy: [SortDescriptor(\.id)])) { row, context, inventory in
            guard row.ownerID == scope.ownerID, row.inventoryGeneration == scope.generation else { throw SharedMediaStorageFailure.conflict }
            switch try SharedMediaNativeAcquisitionGraph.scopedReceipt(row, inventory: inventory, context: context, format: format, checkpoint: check) {
            case .reserved(let request), .held(let request):
                _ = try package(request.packageID, context: context, inventory: inventory)
                guard futureReferences.insert(request.referenceID).inserted,
                      futureReferences.count <= PhotoPreparationPolicy.maximumPackages * 2 else { throw SharedMediaStorageFailure.conflict }
            case .completed: break // Current logical owners are reached through the physical allocation below.
            case .released: break // Stripped terminal rows do not prove any physical release.
            }
        }
        let consumers = try await page(FetchDescriptor<SharedMediaConsumerRecord>(
            predicate: #Predicate { $0.inventoryID == id }, sortBy: [SortDescriptor(\.id)])) { row, context, inventory in
            guard row.ownerID == scope.ownerID, row.inventoryGeneration == scope.generation else { throw SharedMediaStorageFailure.conflict }
            _ = try package(row.packageID, context: context, inventory: inventory)
            _ = try SharedMediaNativeConsumerGraph.validateScoped(row, context: context, format: format, checkpoint: check)
        }
        _ = try await page(FetchDescriptor<SharedMediaDerivativePairRecord>(
            predicate: #Predicate { $0.inventoryID == id }, sortBy: [SortDescriptor(\.id)])) { row, context, inventory in
            try pair(row, context: context, inventory: inventory)
        }
        let allocations = try await page(FetchDescriptor<SharedMediaAllocationRecord>(
            predicate: #Predicate { $0.inventoryID == id }, sortBy: [SortDescriptor(\.id)])) { row, context, inventory in
            guard row.accountID == scope.ownerID, row.namespaceRaw == SharedMediaPhotoLedger.namespace else { throw SharedMediaStorageFailure.conflict }
            try asset(row.id, context: context, inventory: inventory)
        }
        _ = try await page(FetchDescriptor<SharedMediaAssetReferenceCountRecord>(
            predicate: #Predicate { $0.inventoryID == id }, sortBy: [SortDescriptor(\.id)])) { row, context, inventory in
            guard row.ownerID == scope.ownerID, row.inventoryGeneration == scope.generation else { throw SharedMediaStorageFailure.conflict }
            try asset(row.id, context: context, inventory: inventory)
        }
        // Accountless inbox admission is not part of this exact native profile.
        _ = try await page(FetchDescriptor<SharedMediaInboxSourceRecord>(
            predicate: #Predicate { $0.inventoryID == id }, sortBy: [SortDescriptor(\.id)])) { _, _, _ in
            throw SharedMediaStorageFailure.closed
        }
        try check(); _ = try header(freshContext())
        return .init(inventory: expected, pendingPackages: count, consumers: consumers,
            receipts: receipts, allocations: allocations)
    }

    private func pending() throws -> Int {
        try check()
        let context = freshContext(), inventory = try header(context)
        let graph = try SharedMediaPendingGraph.deriveScoped(in: context, inventory: inventory, ownerID: scope.ownerID, format: format)
        guard graph.sources.isEmpty, graph.handoffs.isEmpty else { throw SharedMediaStorageFailure.closed }
        var active = 0
        for row in graph.packages {
            try Task.checkCancellation(); try check()
            _ = try package(row.id, context: context, inventory: inventory)
            let envelope = try SharedMediaNativeDraftEnvelope.decode(row.supportingContextData)
            active += envelope.attempt == nil ? 0 : 1
        }
        active += graph.pairs.filter { $0.phaseRaw != "ready" }.count
        guard active <= 1 else { throw SharedMediaStorageFailure.conflict }
        _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context, inventory: inventory, ownerID: scope.ownerID, format: format, checkpoint: check)
        try check(); _ = try header(context)
        return graph.packages.count
    }

    private func package(_ id: UUID, context: ModelContext, inventory: SharedMediaInventoryRecord) throws -> PhotoPreparationRecord {
        let row = try one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id }))
        guard row.ownerID == scope.ownerID else { throw SharedMediaStorageFailure.conflict }
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

    private func pair(_ row: SharedMediaDerivativePairRecord, context: ModelContext, inventory: SharedMediaInventoryRecord) throws {
        guard row.inventoryID == scope.inventoryID, row.inventoryGeneration == scope.generation,
              row.ownerID == scope.ownerID else { throw SharedMediaStorageFailure.conflict }
        let owner = try package(row.packageID, context: context, inventory: inventory)
        guard case .preparation(let envelope) = try SharedMediaNativeDraftEnvelope.decode(owner.supportingContextData),
              try SharedMediaNativePairPlanGraph.select(envelope, pairID: row.id) != nil else { throw SharedMediaStorageFailure.conflict }
    }

    private func asset(_ id: UUID, context: ModelContext, inventory: SharedMediaInventoryRecord) throws {
        if let work = try SharedMediaNativePairFileGraph.nativeWork(assetID: id, context: context) {
            let pairID = work.pairID
            let row = try one(context, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == pairID }))
            try pair(row, context: context, inventory: inventory)
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
                    _ = try package(ref.packageID, context: context, inventory: inventory)
                }
                if refs.count < SharedMediaStoragePolicy.pageSize { break }
                let (next, overflow) = offset.addingReportingOverflow(refs.count)
                guard !overflow else { throw SharedMediaStorageFailure.capacity }; offset = next
            }
        } else {
            switch value {
            case .reserved(let request), .held(let request): _ = try package(request.packageID, context: context, inventory: inventory)
            default: throw SharedMediaStorageFailure.conflict
            }
        }
    }

    private func freshContext() -> ModelContext {
        let context = ModelContext(container); context.autosaveEnabled = false; return context
    }
    private func header(_ context: ModelContext) throws -> SharedMediaInventoryRecord {
        guard !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let row = try format.header(context: context, scope: scope)
        // Recheck complete bounded prepared joins at every initial/page/final
        // boundary. Legacy V1 and unsupported phases remain closed.
        if format == .appV2 {
            _ = try SharedMediaNativeReceivingIntentGraph.read(context, inventory: row)
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
        body: (T, ModelContext, SharedMediaInventoryRecord) throws -> Void) async throws -> Int64 {
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
        body: (T, ModelContext, SharedMediaInventoryRecord) throws -> Void) throws -> Int {
        let context = freshContext(), inventory = try header(context)
        var query = descriptor; query.fetchLimit = SharedMediaStoragePolicy.pageSize; query.fetchOffset = offset
        let rows = try context.fetch(query)
        for row in rows { try Task.checkCancellation(); try check(); try body(row, context, inventory) }
        try check(); _ = try header(context)
        return rows.count
    }
    private func one<T: PersistentModel>(_ context: ModelContext, _ query: FetchDescriptor<T>) throws -> T {
        try SharedMediaNativePairPlanGraph.one(context, query)
    }
}
