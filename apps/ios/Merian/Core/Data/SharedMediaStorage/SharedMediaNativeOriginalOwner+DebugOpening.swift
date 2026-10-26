#if DEBUG
import Foundation
import SwiftData

/// Existing qualification façades only. Typed commands carry inputs and return
/// snapshots; they cannot read owner state, retain repositories or mint grants.
@MainActor
extension SharedMediaNativeOriginalOwner {
    static func qualification(account: PhotoOriginalPreparationOwner.AccountAccess, drain: SharedMediaNativeOriginalDrain) throws -> SharedMediaNativeOriginalOwner {
        try debugOwner(account: account, drain: drain, kind: .qualification)
    }
    static func appInitialization(account: PhotoOriginalPreparationOwner.AccountAccess, drain: SharedMediaNativeOriginalDrain) throws -> SharedMediaNativeOriginalOwner {
        try debugOwner(account: account, drain: drain, kind: .appInitialization)
    }
    static func appDispatch(account: PhotoOriginalPreparationOwner.AccountAccess, drain: SharedMediaNativeOriginalDrain) throws -> SharedMediaNativeOriginalOwner {
        try debugOwner(account: account, drain: drain, kind: .appDispatch)
    }
    static func scopedInspection(account: PhotoOriginalPreparationOwner.AccountAccess, drain: SharedMediaNativeOriginalDrain) throws -> SharedMediaNativeOriginalOwner {
        try debugOwner(account: account, drain: drain, kind: .scopedInspection)
    }
    func open(container: ModelContainer, authorityRoot: URL, photoRoot: URL, inboxRoot: URL,
              inventoryID: UUID, pause: (@Sendable () async -> Void)? = nil) async throws -> SharedMediaNativeOriginalSnapshot {
        let result = try await debugOpen(container: container, request: .qualification(authorityRoot, photoRoot, inboxRoot, inventoryID, pause))
        guard case .qualification(let snapshot) = result else { throw SharedMediaStorageFailure.closed }; return snapshot
    }
    func initializeApp(container: ModelContainer, parent: URL, inventoryID: UUID,
                       fault: ((SharedMediaNativeBootstrapBoundary) throws -> Void)? = nil,
                       availableBytes: Int64? = nil, discovery: SharedMediaNativeBootstrapDiscovery? = nil) async throws -> SharedMediaStorageSnapshot {
        let result = try await debugOpen(container: container, request: .initialization(parent, inventoryID, fault, availableBytes, discovery))
        guard case .initialization(let snapshot) = result else { throw SharedMediaStorageFailure.closed }; return snapshot
    }
    func openApp(container: ModelContainer, parent: URL, inventoryID: UUID, pause: (@Sendable () async -> Void)? = nil,
                 inspectionTrace: SharedMediaNativeDebugHooks.InspectionTrace? = nil,
                 discovery: SharedMediaNativeBootstrapDiscovery? = nil) async throws -> SharedMediaNativeScopedSnapshot {
        let result = try await debugOpen(container: container, request: .existing(parent, inventoryID, pause, inspectionTrace, discovery))
        guard case .dispatch(let snapshot) = result else { throw SharedMediaStorageFailure.closed }; return snapshot
    }
    func openScoped(container: ModelContainer, authorityRoot: URL, photoRoot: URL, inboxRoot: URL,
                    inventoryID: UUID, pagePause: (@Sendable () async -> Void)? = nil) async throws -> SharedMediaNativeScopedSnapshot {
        let result = try await debugOpen(container: container, request: .scoped(authorityRoot, photoRoot, inboxRoot, inventoryID, pagePause))
        guard case .dispatch(let snapshot) = result else { throw SharedMediaStorageFailure.closed }; return snapshot
    }
}

@MainActor
enum SharedMediaNativeDebugOpenRequest {
    case qualification(URL, URL, URL, UUID, (@Sendable () async -> Void)?)
    case initialization(URL, UUID, ((SharedMediaNativeBootstrapBoundary) throws -> Void)?, Int64?, SharedMediaNativeBootstrapDiscovery?)
    case existing(URL, UUID, (@Sendable () async -> Void)?, SharedMediaNativeDebugHooks.InspectionTrace?, SharedMediaNativeBootstrapDiscovery?)
    case scoped(URL, URL, URL, UUID, (@Sendable () async -> Void)?)
    var kind: SharedMediaNativeOriginalOpenKind {
        switch self {
        case .qualification: .qualification
        case .initialization: .appInitialization
        case .existing: .appDispatch
        case .scoped: .scopedInspection
        }
    }
    var discovery: SharedMediaNativeBootstrapDiscovery? {
        switch self {
        case .initialization(_, _, _, _, let discovery), .existing(_, _, _, _, let discovery): discovery
        default: nil
        }
    }
}
#endif
