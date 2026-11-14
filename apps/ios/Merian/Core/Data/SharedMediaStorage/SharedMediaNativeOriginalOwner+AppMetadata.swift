import Foundation

@MainActor
extension SharedMediaNativeOriginalOwner {
    func prepareAppMetadata(packageID: UUID, draftGeneration: UUID, contexts: [ObservationContext],
                            presentation: [PhotoPreparationImagePresentation]? = nil) async throws -> SharedMediaNativeAppMetadataRequest {
        try await appMetadataWorkflow { try $0.request(packageID: packageID, draftGeneration: draftGeneration, contexts: contexts, presentation: presentation) }
    }
    func currentAppMetadata(packageID: UUID, draftGeneration: UUID) async throws -> SharedMediaNativeAppMetadataRequest {
        try await appMetadataWorkflow { try $0.current(packageID: packageID, draftGeneration: draftGeneration) }
    }
    func saveAppMetadata(_ request: SharedMediaNativeAppMetadataRequest) async throws -> Int64 {
        try await appMetadataWorkflow { try $0.apply(request) }
    }
}
