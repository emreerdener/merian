import Foundation

/// Typed test controls only; never account, file or mutation authority. The
/// registered owner supplies the instance through its sealed grants.
#if DEBUG
@MainActor
final class SharedMediaNativeDebugHooks {
    init() {}
    var lifecycleFault: ((SharedMediaNativeLifecycleBoundary) throws -> Void)?
    var preparationAvailableBytes: Int64?
    var preparationFocusFactory = ImageFocusWorkFactory()
    var preparationFault: ((SharedMediaNativePreparationBoundary) throws -> Void)?
    var metadataFault: ((SharedMediaNativeMetadataBoundary) throws -> Void)?
    var metadataAvailableBytes: Int64?
    var inspectionAuditCount = 0
    var acquisitionFault: ((SharedMediaNativeAcquisitionBoundary) throws -> Void)?
    var bootstrapFault: ((SharedMediaNativeBootstrapBoundary) throws -> Void)?
    var bootstrapAvailableBytes: Int64?
    var scopedPagePause: (@Sendable () async -> Void)?
}
#endif

enum SharedMediaNativeInitializationBoundary: Sendable {
    case afterPhotoBinding, afterInboxBinding, afterAuthorityBinding, beforeSave, afterSave
}
