struct CandidateSwipeSession: Equatable {
    let originalCandidates: [IdentificationCandidate]
    private(set) var remainingCandidates: [IdentificationCandidate]
    private(set) var confirmedCandidate: IdentificationCandidate?

    init(candidates: [IdentificationCandidate]) {
        self.originalCandidates = candidates
        self.remainingCandidates = candidates
    }

    var isExhausted: Bool {
        remainingCandidates.isEmpty && confirmedCandidate == nil
    }

    var topCandidate: IdentificationCandidate? {
        remainingCandidates.first
    }

    mutating func restart() {
        remainingCandidates = originalCandidates
        confirmedCandidate = nil
    }

    mutating func confirm(_ candidate: IdentificationCandidate) {
        confirmedCandidate = candidate
        remainingCandidates.removeAll { $0.scientificName == candidate.scientificName }
    }

    mutating func reject(scientificName: String) {
        remainingCandidates.removeAll { $0.scientificName == scientificName }
    }

    mutating func rejectTopCandidate() {
        guard !remainingCandidates.isEmpty else { return }
        remainingCandidates.removeFirst()
    }

    mutating func skipTopCandidate() {
        guard remainingCandidates.count > 1 else { return }
        let top = remainingCandidates.removeFirst()
        remainingCandidates.append(top)
    }

    static func == (lhs: CandidateSwipeSession, rhs: CandidateSwipeSession) -> Bool {
        lhs.originalCandidates.map(\.scientificName) == rhs.originalCandidates.map(\.scientificName) &&
            lhs.remainingCandidates.map(\.scientificName) == rhs.remainingCandidates.map(\.scientificName) &&
            lhs.confirmedCandidate?.scientificName == rhs.confirmedCandidate?.scientificName
    }
}
