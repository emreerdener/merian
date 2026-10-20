import Foundation
import SwiftData

/// V1 typed operations under the repository's existing sealed dispatch authority.
/// No binding/fence constructor, app authority or raw path escapes this helper.
@MainActor
struct SharedMediaNativeQualificationOperations {
    private let container: ModelContainer
    private let inventoryID: UUID
    private let authority: SharedMediaNativeMutationAuthority
    private let checkDispatch: () throws -> Void
    private let originalIO: SharedMediaNativeOriginalIO
    private let availableBytes: () throws -> Int64
    private let verifyProof: (SharedMediaPhotoRetirementInspection) throws -> Void
    private let acquisitionBoundary: (SharedMediaNativeAcquisitionBoundary) throws -> Void
    private let metadataBoundary: (SharedMediaNativeMetadataBoundary) throws -> Void
    #if DEBUG
    private var debug: SharedMediaNativeDebugHooks?
    #endif
    init(container: ModelContainer, inventoryID: UUID, authority: SharedMediaNativeMutationAuthority,
         io: SharedMediaNativeOriginalIO, checkDispatch: @escaping () throws -> Void, availableBytes: @escaping () throws -> Int64,
         verifyProof: @escaping (SharedMediaPhotoRetirementInspection) throws -> Void,
         acquisitionBoundary: @escaping (SharedMediaNativeAcquisitionBoundary) throws -> Void,
         metadataBoundary: @escaping (SharedMediaNativeMetadataBoundary) throws -> Void) {
        self.container = container; self.inventoryID = inventoryID; self.authority = authority; originalIO = io
        self.checkDispatch = checkDispatch; self.availableBytes = availableBytes; self.verifyProof = verifyProof
        self.acquisitionBoundary = acquisitionBoundary; self.metadataBoundary = metadataBoundary
        #if DEBUG
        debug = nil
        #endif
    }
    #if DEBUG
    func withDebug(_ value: SharedMediaNativeDebugHooks?) -> Self {
        var result = self; result.debug = value; return result
    }
    #endif
    func originalReadback() throws -> SharedMediaNativeOriginalReadback {
        try checkDispatch()
        return .init(container: container, inventoryID: inventoryID, authority: authority)
    }
    func originalReceipt(_ request: SharedMediaAcquisitionIntent) throws -> SharedMediaAcquisitionReceipt? {
        try checkDispatch()
        try acquisitionBoundary(.beforeReadback)
        return try originalReadback().receipt(request)
    }
    func reservedState(_ request: SharedMediaAcquisitionIntent) throws -> SharedMediaNativeReservedState {
        try checkDispatch()
        try acquisitionBoundary(.beforeReadback)
        return try originalReadback().reservedState(request)
    }

    func reserveOriginal(_ request: SharedMediaAcquisitionIntent) throws {
        try checkDispatch(); try authority.validate()
        let transaction = try SharedMediaNativeAcquisitionMutation.reserve(container: container, request: request,
            authority: authority, availableBytes: availableBytes())
        try acquisitionBoundary(.beforeReservationSave); try transaction.save(); try acquisitionBoundary(.afterReservationSave)
    }

    func writeOriginal(_ data: Data, request: SharedMediaAcquisitionIntent) async throws -> SharedMediaPhotoRetirementInspection {
        try checkDispatch()
        let proof = try await originalIO.write(data, request: request)
        try checkDispatch()
        try acquisitionBoundary(.afterOriginalWrite)
        return proof
    }
    func loadOriginal(_ provider: @Sendable () async throws -> Data) async throws -> Data {
        try checkDispatch()
        let data = try await originalIO.load(provider)
        try checkDispatch()
        return data
    }

    func completeOriginal(_ request: SharedMediaAcquisitionIntent, proof: SharedMediaPhotoRetirementInspection) throws {
        try checkDispatch()
        let transaction = try SharedMediaNativeAcquisitionMutation.complete(container: container, request: request,
            authority: authority, proof: proof)
        try acquisitionBoundary(.beforeCompletionSave); try transaction.save(); try acquisitionBoundary(.afterCompletionSave)
    }
    func metadata(packageID: UUID) throws -> SharedMediaNativeMetadataMutation {
        try checkDispatch()
        try metadataBoundary(.beforeReadback)
        return try .init(container: container, inventoryID: inventoryID, packageID: packageID, authority: authority)
    }
    func saveMetadata(_ request: SharedMediaNativeMetadataRequest) throws -> Int64 {
        try checkDispatch()
        var available = try availableBytes()
        #if DEBUG
        if let limit = debug?.metadataAvailableBytes { available = min(available, limit) }
        #endif
        return try SharedMediaNativeQualificationPersistence.metadata(container: container, request: request,
            authority: authority, available: available, boundary: metadataBoundary)
    }
    func preparationOperations() throws -> SharedMediaNativePreparationOperations {
        try checkDispatch()
        var focusFactory = ImageFocusWorkFactory()
        #if DEBUG
        focusFactory = debug?.preparationFocusFactory ?? focusFactory
        #endif
        return try .init(container: container, inventoryID: inventoryID, authority: authority, io: originalIO, focusFactory: focusFactory,
            verifyFreezeProofs: { proofs in
                for proof in proofs { try self.verifyProof(proof) }
            }, availableBytes: {
                let available = try self.availableBytes()
                #if DEBUG
                if let limit = self.debug?.preparationAvailableBytes { return min(available, limit) }
                #endif
                return available
            }, boundary: { point in
                #if DEBUG
                try self.debug?.preparationFault?(point)
                #endif
            })
    }
    func lifecycleOperations() throws -> SharedMediaNativeLifecycleOperations {
        try checkDispatch()
        return try .init(container: container, inventoryID: inventoryID, authority: authority, io: originalIO,
            availableBytes: { try self.availableBytes() }, boundary: { try self.lifecycleBoundary($0) })
    }
    private func lifecycleBoundary(_ point: SharedMediaNativeLifecycleBoundary) throws {
        #if DEBUG
        try debug?.lifecycleFault?(point)
        #endif
    }
}
