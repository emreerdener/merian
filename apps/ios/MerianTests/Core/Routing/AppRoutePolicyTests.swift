import Foundation
@testable import Merian
import Testing

@Suite("App route policy")
struct AppRoutePolicyTests {
    @Test func semanticCoalescingNormalizesStableIdentifiers() {
        #expect(
            AppRoute.scan(scanId: " Scan-ID ").coalesces(
                with: .scan(scanId: "scan-id")
            )
        )
        #expect(AppRoute.identifyNature.coalesces(with: .openScanner))
        #expect(
            AppRoute.refinement(
                scanId: "SCAN-ID",
                initialDescription: "old",
                entryPoint: .standard
            ).coalesces(
                with: .refinement(
                    scanId: "scan-id",
                    initialDescription: "new",
                    entryPoint: .standard
                )
            )
        )
        #expect(
            !AppRoute.refinement(
                scanId: "scan-id",
                initialDescription: nil,
                entryPoint: .standard
            ).coalesces(
                with: .refinement(
                    scanId: "scan-id",
                    initialDescription: nil,
                    entryPoint: .nonBiologicalCorrection
                )
            )
        )
        #expect(
            !AppRoute.explorePost(
                postId: "post-id",
                targetCommentId: "comment-a",
                targetReplyParentCommentId: nil
            ).coalesces(
                with: .explorePost(
                    postId: "post-id",
                    targetCommentId: "comment-b",
                    targetReplyParentCommentId: nil
                )
            )
        )
    }

    @Test func sourcePolicyPreservesPriorityLifetimeAndSessionRules() {
        #expect(AppRouteSource.durableExternalImport.priority == .durableExternalImport)
        #expect(AppRouteSource.deepLink.priority == .explicitExternal)
        #expect(AppRouteSource.pushNotification.priority == .explicitExternal)
        #expect(AppRouteSource.appIntent.priority == .explicitExternal)
        #expect(AppRouteSource.internalUserAction.priority == .internalUserAction)
        #expect(AppRouteSource.genericLaunch.priority == .genericLaunch)
        #expect(AppRouteSource.debug.priority == .debug)

        #expect(AppRouteSource.durableExternalImport.lifetime == nil)
        #expect(AppRouteSource.deepLink.lifetime == 300)
        #expect(AppRouteSource.pushNotification.lifetime == 300)
        #expect(AppRouteSource.appIntent.lifetime == 120)
        #expect(AppRouteSource.internalUserAction.lifetime == 30)
        #expect(AppRouteSource.genericLaunch.lifetime == 15)
        #expect(AppRouteSource.debug.lifetime == 30)

        #expect(AppRouteSource.durableExternalImport.survivesSessionReset)
        #expect(AppRouteSource.deepLink.survivesSessionReset)
        #expect(AppRouteSource.pushNotification.survivesSessionReset)
        #expect(AppRouteSource.appIntent.survivesSessionReset)
        #expect(!AppRouteSource.internalUserAction.survivesSessionReset)
        #expect(!AppRouteSource.genericLaunch.survivesSessionReset)
        #expect(!AppRouteSource.debug.survivesSessionReset)
    }

    @Test func accountAndOutcomePolicyRemainExplicit() {
        #expect(AppRoute.scan(scanId: "scan").isAccountSensitive)
        #expect(AppRoute.fieldTrips.isAccountSensitive)
        #expect(AppRoute.proAccessRequired.isAccountSensitive)
        #expect(!AppRoute.explorePost(
            postId: "post",
            targetCommentId: nil,
            targetReplyParentCommentId: nil
        ).isAccountSensitive)
        #expect(!AppRoute.speciesDictionary(speciesId: "species").isAccountSensitive)
        #expect(!AppRoute.processExternalImageImports.isAccountSensitive)

        #expect(AppRouteOutcome.applied(presentationID: nil).isTerminal)
        #expect(!AppRouteOutcome.applied(presentationID: UUID()).isTerminal)
        #expect(!AppRouteOutcome.deferred(reason: .presentationOccupied).isTerminal)
        #expect(AppRouteOutcome.dismissed(presentationID: UUID()).isTerminal)
        #expect(AppRouteOutcome.rejected(reason: .expired).isTerminal)
    }
}
