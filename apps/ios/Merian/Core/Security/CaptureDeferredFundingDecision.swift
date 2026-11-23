import Foundation

/// Pure projection of the existing deferred-admission policy. Each blocker must
/// have a current durable ownership proof; absence is never a released credit.
struct CaptureDeferredFundingDecision: Equatable, Sendable {
    struct Evidence: Codable, Equatable, Sendable {
        let ownerID: UUID
        let sessionGeneration: UUID
        let entitlementVersion: Int
        let paidAvailable: Bool
        let complimentaryAvailable: Bool
        let availableCredits: Int
        let blockerStates: [String: String]
        let unresolvedBlockers: [String]
        let ownershipProofs: [String: String]
    }
    let original: ScanFundingReservation
    let effective: ScanFundingReservation
    let evidence: Evidence

    init?(original: ScanFundingReservation, evidence: Evidence) {
        guard original.source == .deferredFlash, original.accountId == evidence.ownerID,
              evidence.entitlementVersion >= 0, evidence.availableCredits >= 0,
              !original.blockerScanIds.isEmpty,
              original.blockerScanIds.allSatisfy({ evidence.ownershipProofs[$0].map(SharedMediaAcquisitionEncoding.isHash) == true }),
              evidence.ownershipProofs[original.scanId].map(SharedMediaAcquisitionEncoding.isHash) == true else { return nil }
        let states = original.blockerScanIds.map { evidence.blockerStates[$0] }
        var effective = original
        if evidence.paidAvailable {
            effective.source = .paidPro
        } else if states.allSatisfy({ $0 == ComplimentaryScanState.held.rawValue || $0 == ComplimentaryScanState.consumed.rawValue }) {
            effective.source = .immediateFlash
        } else if states.allSatisfy({ $0 == ComplimentaryScanState.held.rawValue ||
            $0 == ComplimentaryScanState.consumed.rawValue || $0 == ComplimentaryScanState.released.rawValue }),
                  states.contains(ComplimentaryScanState.released.rawValue) {
            if evidence.complimentaryAvailable && evidence.availableCredits > 0 {
                effective.source = .complimentaryPro
            } else if evidence.unresolvedBlockers.filter({ $0 != original.scanId }).isEmpty {
                effective.source = .immediateFlash
            } else { return nil }
        } else { return nil }
        effective.blockerScanIds = []
        self.original = original; self.effective = effective; self.evidence = evidence
    }

    var evidenceSHA256: String {
        get throws { try SharedMediaAcquisitionEncoding.digest(SharedMediaAcquisitionEncoding.encode(evidence, maximum: 32768)) }
    }
}
