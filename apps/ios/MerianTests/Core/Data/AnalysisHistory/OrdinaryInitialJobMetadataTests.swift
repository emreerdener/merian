import Foundation
@testable import Merian
import Testing

struct OrdinaryInitialJobMetadataTests {
    @Test func acceptanceMetadataBindsOwnerScanAndGenerationWithoutReplacingFunding() throws {
        let identity = OrdinaryInitialSubmissionIdentity(ownerID: UUID(), scanID: UUID(), generation: UUID())
        let funding = ScanFundingReservation(accountId: identity.ownerID, scanId: identity.scanID.uuidString,
            source: .deferredFlash, blockerScanIds: [UUID().uuidString], createdAt: Date(timeIntervalSince1970: 1))
        let value = try OrdinaryInitialJobMetadata(identity: identity, funding: funding)
        try value.requireInitialReadback(value.json)
        #expect(OfflineScanJobMetadataContract.funding(in: value.json) == funding)
        #expect(InferenceGenerationMetadataContract.generation(in: value.json) == identity.generation)
        #expect(!funding.allowsDispatch)
        let changedOwner = OrdinaryInitialSubmissionIdentity(ownerID: UUID(), scanID: identity.scanID, generation: identity.generation)
        let changedScan = OrdinaryInitialSubmissionIdentity(ownerID: identity.ownerID, scanID: UUID(), generation: identity.generation)
        for changed in [changedOwner, changedScan] {
            #expect(throws: (any Error).self) { try OrdinaryInitialJobMetadata(identity: changed, funding: funding) }
        }
        let changedGeneration = try OrdinaryInitialJobMetadata(identity: .init(ownerID: identity.ownerID,
            scanID: identity.scanID, generation: UUID()), funding: funding)
        #expect(throws: (any Error).self) { try value.requireInitialReadback(changedGeneration.json) }
        #expect(throws: (any Error).self) {
            try value.requireInitialReadback(OfflineScanJobMetadataContract.markingFundingReleased(in: value.json))
        }
        var injected = OfflineScanJobMetadataContract.object(from: value.json)
        injected[OrdinaryInitialEvidenceProof.completionKey] = [:]
        #expect(throws: (any Error).self) {
            try value.requireInitialReadback(OfflineScanJobMetadataContract.json(from: injected))
        }
    }
}
