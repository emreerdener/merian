import Testing
@testable import Merian

struct CandidateSwipeSessionTests {
    @Test func testRejectSkipRestartAndConfirmMutateCandidateStack() {
        let monarch = IdentificationCandidate(scientificName: "Danaus plexippus", commonName: "Monarch", confidenceScore: 0.81)
        let viceroy = IdentificationCandidate(scientificName: "Limenitis archippus", commonName: "Viceroy", confidenceScore: 0.71)
        let queen = IdentificationCandidate(scientificName: "Danaus gilippus", commonName: "Queen", confidenceScore: 0.58)
        var session = CandidateSwipeSession(candidates: [monarch, viceroy, queen])

        #expect(session.topCandidate?.scientificName == monarch.scientificName)

        session.skipTopCandidate()
        #expect(session.remainingCandidates.map(\.scientificName) == [
            viceroy.scientificName,
            queen.scientificName,
            monarch.scientificName
        ])

        session.rejectTopCandidate()
        #expect(session.remainingCandidates.map(\.scientificName) == [
            queen.scientificName,
            monarch.scientificName
        ])

        session.confirm(queen)
        #expect(session.confirmedCandidate?.scientificName == queen.scientificName)
        #expect(session.remainingCandidates.map(\.scientificName) == [monarch.scientificName])
        #expect(session.isExhausted == false)

        session.restart()
        #expect(session.confirmedCandidate?.scientificName == nil)
        #expect(session.remainingCandidates.map(\.scientificName) == [
            monarch.scientificName,
            viceroy.scientificName,
            queen.scientificName
        ])
    }

    @Test func testSessionReportsExhaustedOnlyWithoutConfirmedCandidate() {
        let candidate = IdentificationCandidate(scientificName: "Danaus plexippus", confidenceScore: 0.81)
        var session = CandidateSwipeSession(candidates: [candidate])

        session.rejectTopCandidate()
        #expect(session.isExhausted == true)

        session.restart()
        session.confirm(candidate)
        #expect(session.isExhausted == false)
    }
}
