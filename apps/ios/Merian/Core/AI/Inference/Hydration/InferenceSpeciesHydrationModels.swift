import Foundation
import SwiftData

extension InferenceSpeciesHydrationCoordinator {
    enum ReferencePolicy: Sendable, Equatable {
        case none
        case showLoadingWhenReferenceMissing
    }

    enum LoadingScope: Sendable, Equatable {
        case metadata
        case lookalikes
    }

    enum FailureScope: Sendable, Equatable {
        case wikipedia
        case gbif
        case metadata
        case lookalikes
    }

    struct Identity: Sendable, Equatable {
        let scanId: String
        let scientificName: String
        let presentationGeneration: UInt64
        let reviewActionGeneration: UInt64?
    }

    struct LiveRequest: Sendable {
        let speciesData: SpeciesData
        let modelContainer: ModelContainer?
        let referencePolicy: ReferencePolicy
        let presentationGeneration: UInt64
        let reviewActionGeneration: UInt64
    }

    struct WikipediaRequest: Sendable {
        let identity: Identity
        let modelContainer: ModelContainer?
    }

    struct GBIFRequest: Sendable {
        let taxonKey: Int
        let identity: Identity
        let modelContainer: ModelContainer?
    }

    struct EnrichmentRequest: Sendable {
        let modelContainer: ModelContainer?
        let needsMetadata: Bool
        let needsLookalikes: Bool
        let allowLookalikesRetry: Bool
        let reviewActionGeneration: UInt64?

        init(
            modelContainer: ModelContainer?,
            needsMetadata: Bool = true,
            needsLookalikes: Bool = true,
            allowLookalikesRetry: Bool = true,
            reviewActionGeneration: UInt64? = nil
        ) {
            self.modelContainer = modelContainer
            self.needsMetadata = needsMetadata
            self.needsLookalikes = needsLookalikes
            self.allowLookalikesRetry = allowLookalikesRetry
            self.reviewActionGeneration = reviewActionGeneration
        }
    }

    struct PersistenceWork: Sendable {
        let identity: Identity
        let operation: @Sendable () async -> Void
    }

    struct Callbacks: Sendable {
        let currentSpeciesData: @MainActor @Sendable () -> SpeciesData?
        let currentReferenceState: @MainActor @Sendable () -> ReferenceState
        let currentPresentationGeneration: @MainActor @Sendable () -> UInt64
        let isPresentationCurrent:
            @MainActor @Sendable (Identity) -> Bool
        let publishSpeciesData:
            @MainActor @Sendable (SpeciesData) -> Void
        let publishReferenceState:
            @MainActor @Sendable (ReferenceState) -> Void
        let setLoading:
            @MainActor @Sendable (LoadingScope, Bool) -> Void
        let enqueuePersistence:
            @MainActor @Sendable (PersistenceWork) -> Void
    }

    struct Dependencies: Sendable {
        let logWikipediaResponse:
            @MainActor @Sendable (_ imageURL: String?) -> Void
        let logWikipediaApplied:
            @MainActor @Sendable (_ urls: [String]) -> Void
        let logGBIFResponse:
            @MainActor @Sendable (_ urls: [String]) -> Void
        let logFailure:
            @MainActor @Sendable (_ scope: FailureScope, _ error: Error) -> Void
    }
}
