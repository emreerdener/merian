import Foundation
@testable import Merian
import Testing

@Suite("Ghost Profile Merge Policy")
struct GhostProfileMergePolicyTests {
    @Test func replacementKeepsUnrelatedProofsInStableOrder() {
        let replaced = makeHandoff(
            ghostUserId: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA",
            handoffId: "11111111-1111-4111-8111-111111111111"
        )
        let unrelated = makeHandoff(
            ghostUserId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            handoffId: "22222222-2222-4222-8222-222222222222"
        )
        let replacement = makeHandoff(
            ghostUserId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            handoffId: "33333333-3333-4333-8333-333333333333"
        )

        let updated = GhostProfileMergePolicy.enqueuing(
            replacement,
            in: [replaced, unrelated]
        )

        #expect(updated == [unrelated, replacement])
    }

    @Test func terminalServerCodesAloneDiscardDurableProof() {
        #expect(
            GhostProfileMergePolicy.shouldDiscardPendingHandoff(
                serverCode: "handoff_expired"
            )
        )
        #expect(
            GhostProfileMergePolicy.shouldDiscardPendingHandoff(
                serverCode: "handoff_invalid"
            )
        )
        for retryableCode in [
            "handoff_forbidden",
            "auth_cleanup_pending",
            "merge_temporarily_unavailable",
            nil
        ] {
            #expect(
                !GhostProfileMergePolicy.shouldDiscardPendingHandoff(
                    serverCode: retryableCode
                )
            )
        }
    }

    private func makeHandoff(
        ghostUserId: String,
        handoffId: String
    ) -> PendingGhostProfileMerge {
        PendingGhostProfileMerge(
            ghostUserId: ghostUserId,
            provider: "apple",
            providerSubject: "provider-subject",
            handoffId: handoffId,
            handoffSecret: String(repeating: "s", count: 43),
            expiresAt: "2026-10-05T12:00:00Z"
        )
    }
}
