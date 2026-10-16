import Foundation

/// Prepare synchronously at the actual tap, before any child presentation closes.
typealias CandidateReviewPreparation = @MainActor () -> CandidateReviewTicket?

/// One-use presentation handoff only. It neither confirms nor owns durable work.
@MainActor
final class CandidateReviewTicket {
    private var present: (() -> Bool)?
    private var discard: (() -> Void)?
    init(present: @escaping () -> Bool, discard: @escaping () -> Void) {
        self.present = present; self.discard = discard
    }
    func resume() {
        let present = present, discard = discard
        self.present = nil; self.discard = nil
        guard let present else { return }
        if !present() { discard?() }
    }
    func cancel() {
        let discard = discard
        present = nil; self.discard = nil
        discard?()
    }
}
