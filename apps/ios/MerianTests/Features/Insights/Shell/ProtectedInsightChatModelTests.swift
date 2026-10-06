import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ProtectedInsightChatModelTests {
    @MainActor final class Fixture {
        let support = ProtectedInsightChatPersistenceTests()
        let container: ModelContainer
        let ticket: ProtectedInsightChatTicket
        let baseline: SelectedAnalysisReviewBaseline
        let continuation = ProtectedInsightChatContinuation()
        var current = true
        var failBeforeSave = false
        var failAfterSave = false
        var queueAccepts = true
        var events: [String] = []
        var deliveries: [(ProtectedInsightChatIntent, Bool)] = []
        var generation: UInt64 = 0
        var minted = 0
        var beforeStage: (() throws -> Void)?

        init() async throws {
            (container, ticket) = try await support.seed()
            baseline = try #require(SelectedAnalysisReviewBaseline(scanID: ticket.observationID.uuidString,
                ownerID: ticket.ownerID.uuidString, analysisID: ticket.selection.analysisID.uuidString, revision: ticket.selection.stateRevision))
            continuation.bind(ticket, container: ObjectIdentifier(container))
        }
        func model(shown: SelectedAnalysisReviewBaseline? = nil) throws -> ProtectedInsightChatModel {
            let shown = shown ?? baseline
            var cloud = support.source.support.client(fetch: { _ in throw ObservationHistoryError.unavailable }, current: { self.current })
            cloud.begin = { owner in .init(id: UUID(), session: .init(userID: owner, isAnonymous: false)) }
            let config = ProtectedInsightChatAccess.Configuration(deliver: { intent, admission, container in
                #expect(container === self.container)
                let saved = try? ProtectedInsightChatPersistence.read(intent, container: container, isCurrent: { true })
                #expect(saved?.request == intent.request)
                self.events.append("deliver")
                let replay: Bool
                switch admission {
                case .initial: replay = false
                case .explicitReplay: replay = true
                }
                self.deliveries.append((intent, replay))
                return self.queueAccepts
            }, generation: { self.generation })
            let access = ProtectedInsightChatAccess.prepared(cloud: cloud, configuration: config, session: { id, container in
                try IdentificationHistorySession(observation: id, container: container, cloud: cloud,
                    currentGeneration: { 1 }, sessionIsCurrent: { _ in self.current })
            })
            var session = try access.open(shown, container)
            let stage = session.stage
            session.stage = { request, ticket in
                self.events.append("stage")
                if self.failBeforeSave { throw ObservationHistoryError.unavailable }
                let hook = self.beforeStage; self.beforeStage = nil
                try hook?()
                let saved = try stage(request, ticket)
                if self.failAfterSave { throw ObservationHistoryError.unavailable }
                return saved
            }
            let model = ProtectedInsightChatModel(baseline: shown, session: session, continuation: continuation,
                presentationIsCurrent: { self.current }, makeID: {
                    self.minted += 1
                    return UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", self.minted))!
                })
            model.refresh()
            return model
        }
    }

    @Test func finalTapPersistsBeforeDeliveryAndNeverAutomaticallyRetries() async throws {
        let f = try await Fixture(), model = try f.model()
        model.text = " Synthetic question "
        model.send()
        #expect(f.events == ["stage", "deliver"] && f.minted == 2)
        #expect(f.deliveries.first?.0.request.messageText == "Synthetic question")
        #expect(model.unfinished?.state == .pending && !model.canSend)
        model.sendSaved(); model.send(); model.refresh()
        #expect(f.deliveries.count == 1 && f.minted == 2)
        model.close()
        #expect(model.closed && model.completed.isEmpty && f.deliveries.count == 1)
    }

    @Test func saveUncertaintySurvivesReopeningAndReusesOriginalIDsAndText() async throws {
        let f = try await Fixture(); f.failBeforeSave = true
        let first = try f.model(); first.text = "Original question"; first.send()
        let original = try #require(f.continuation.candidate?.request)
        first.text = "Replacement"; first.send(); first.close()
        let reopened = try f.model()
        #expect(reopened.canRetrySave && !reopened.canSend && f.minted == 2)
        f.failBeforeSave = false; reopened.retrySave()
        #expect(f.deliveries.isEmpty && f.minted == 2 && reopened.unfinished?.intent.request == original)
        reopened.sendSaved()
        #expect(f.deliveries.first?.0.request == original && f.minted == 2)
        #expect(f.continuation.candidate == nil)
    }

    @Test func committedSaveErrorRestoresPendingWithoutAnotherStageOrUUID() async throws {
        let f = try await Fixture(); f.failAfterSave = true
        let first = try f.model(); first.text = "Question"; first.send(); first.close()
        #expect(f.deliveries.isEmpty && f.continuation.candidate != nil)
        let reopened = try f.model()
        #expect(reopened.unfinished?.state == .pending && !reopened.canRetrySave)
        reopened.sendSaved()
        #expect(f.events == ["stage", "deliver"] && f.minted == 2)
    }

    @Test func offlinePendingAndHeldReplayUseExactSavedQuestion() async throws {
        let f = try await Fixture(); f.queueAccepts = false
        let model = try f.model(); model.text = "Question"; model.send()
        let intent = try #require(model.unfinished?.intent)
        #expect(!model.deliveryRequested)
        f.queueAccepts = true; model.sendSaved()
        #expect(f.deliveries.count == 2 && f.deliveries.allSatisfy { $0.0.request == intent.request && !$0.1 })
        let claim = try #require(try ProtectedInsightChatPersistence.claimInitial(intent, at: Date(), container: f.container, isCurrent: { true }))
        model.deliveryFinished(); #expect(!model.canRecover); model.recoverSaved()
        #expect(f.deliveries.count == 2) // A running, unexpired attempt never enters the queue.
        try ProtectedInsightChatPersistence.hold(claim, at: Date(), container: f.container, isCurrent: { true })
        model.refresh(); #expect(model.canRecover); model.recoverSaved()
        #expect(f.deliveries.count == 3 && f.deliveries.last?.1 == true)
        #expect(f.deliveries.last?.0.request == intent.request && f.minted == 2)
    }

    @Test func actualExitRefreshShowsExactReceiptWithoutMutableThread() async throws {
        let f = try await Fixture(), model = try f.model()
        model.text = "Question"; model.send()
        let intent = try #require(model.unfinished?.intent)
        let claim = try #require(try ProtectedInsightChatPersistence.claimInitial(intent, at: Date(), container: f.container, isCurrent: { true }))
        let receipt = try ProtectedInsightChatStatusTests().receipt(intent)
        _ = try ProtectedInsightChatPersistence.acknowledge(receipt, claim: claim, at: Date(), container: f.container, isCurrent: { true })
        f.generation += 1
        #expect(model.deliveryGeneration == 1)
        model.deliveryFinished()
        #expect(model.completed.first?.request == intent.request && model.unfinished == nil && !model.deliveryRequested)
        #expect(f.deliveries.count == 1)
    }

    @Test func staleAuthorityBlocksNewSendButRetainsSavedRecoveryAndAccountLossCloses() async throws {
        let f = try await Fixture(); f.queueAccepts = false
        let model = try f.model(); model.text = "Question"; model.send()
        try f.support.source.update(f.container) { scan, _ in scan.observationStateRevision = 11 }
        model.refresh(); model.sendSaved()
        #expect(f.deliveries.count == 2 && f.minted == 2)
        f.current = false; model.refresh()
        #expect(model.closed && model.unfinished == nil)
        model.sendSaved(); model.recoverSaved()
        #expect(f.deliveries.count == 2)
    }

    @Test func invalidQuestionNeverPersistsAndDisplayChangePreventsNewIdentity() async throws {
        let f = try await Fixture(), model = try f.model()
        model.text = String(repeating: "x", count: 601); model.send()
        #expect(f.events.isEmpty && f.continuation.candidate == nil)
        try f.support.source.update(f.container) { scan, _ in scan.observationStateRevision = 11 }
        model.text = "Valid"; let minted = f.minted; model.send()
        #expect(!model.canSend && f.minted == minted && f.events.isEmpty)
    }
    @Test func expiredRunningRecoveryIsExplicitAndKeepsTheRequest() async throws {
        let f = try await Fixture(); f.queueAccepts = false
        let model = try f.model(); model.text = "Question"; model.send()
        let intent = try #require(model.unfinished?.intent)
        _ = try ProtectedInsightChatPersistence.claimInitial(intent, at: Date().addingTimeInterval(-181), container: f.container, isCurrent: { true })
        model.refresh()
        #expect(f.deliveries.count == 1 && model.unfinished?.state == .running && model.canRecover)
        model.recoverSaved()
        #expect(f.deliveries.count == 2 && f.deliveries.last?.1 == true && f.minted == 2)
        #expect(f.deliveries.last?.0.request == intent.request)
    }

    @Test func reopeningNewRevisionCannotReplaceAnUncertainUnsavedCandidate() async throws {
        let f = try await Fixture(); f.failBeforeSave = true
        let model = try f.model(); model.text = "Original"; model.send(); model.close()
        let candidate = try #require(f.continuation.candidate)
        _ = try await f.support.source.service(data: f.support.source.fixture(revision: 11))
            .syncSelected(observationID: f.ticket.observationID.uuidString, container: f.container)
        let shown = try #require(SelectedAnalysisReviewBaseline(scanID: f.ticket.observationID.uuidString,
            ownerID: f.ticket.ownerID.uuidString, analysisID: f.ticket.selection.analysisID.uuidString, revision: 11))
        let reopened = try f.model(shown: shown); f.failBeforeSave = false
        reopened.retrySave(); reopened.text = "Replacement"; reopened.send()
        #expect(f.continuation.candidate?.request == candidate.request && f.minted == 2 && f.deliveries.isEmpty)
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        f.continuation.clear()
        #expect(f.continuation.candidate == nil)
    }

    @Test func presentationIdentityIncludesTokenAndGeneration() {
        let token = UUID(), scan = UUID().uuidString
        let one = InsightShellPresentation.protectedChat(token: token, scanId: scan, generation: 1)
        #expect(one.id != InsightShellPresentation.protectedChat(token: UUID(), scanId: scan, generation: 1).id)
        #expect(one.id != InsightShellPresentation.protectedChat(token: token, scanId: scan, generation: 2).id)
        #expect(one.id != InsightShellPresentation.chat(scanId: scan, generation: 1).id)
    }

    @Test func proofBlocksFreshSendAfterReopeningEvenWhenLocalTicketStillMatches() async throws {
        let fixture = try await Fixture(), model = try fixture.model()
        model.text = "Question"; model.send()
        let intent = try #require(model.unfinished?.intent), helper = ProtectedInsightChatClaimsTests()
        let claim = try helper.claim(intent, in: fixture.container)
        _ = try ProtectedInsightChatPersistence.acknowledge(helper.proof(intent), claim: claim,
            at: helper.start, container: fixture.container, isCurrent: { true })
        model.deliveryFinished(); model.text = "Replacement"
        #expect(model.requiresIdentificationRefresh && !model.canSend && model.unfinished == nil)
        #expect(model.completed.first?.receiptKind == .notAdmitted)
        model.send(); model.close()
        let reopened = try fixture.model(); reopened.text = "Replacement"; reopened.send()
        #expect(reopened.requiresIdentificationRefresh && !reopened.canSend && fixture.minted == 2)
        #expect(fixture.deliveries.count == 1)
    }

    @Test(arguments: [false, true])
    func finalTapRechecksProofAndOnlyDiscardsProvenUnpersistedCandidate(race: Bool) async throws {
        let fixture = try await Fixture(), model = try fixture.model()
        let installProof = {
            let request = try fixture.support.request(fixture.ticket)
            let saved = try ProtectedInsightChatPersistence.stage(request, ticket: fixture.ticket,
                container: fixture.container, isCurrent: { true })
            let helper = ProtectedInsightChatClaimsTests(), claim = try helper.claim(saved, in: fixture.container)
            _ = try ProtectedInsightChatPersistence.acknowledge(helper.proof(saved), claim: claim,
                at: helper.start, container: fixture.container, isCurrent: { true })
        }
        if race { fixture.beforeStage = installProof } else { try installProof() }
        model.text = "New question"; model.send()
        #expect(model.requiresIdentificationRefresh && !model.canSend && !model.canRetrySave)
        #expect(fixture.continuation.candidate == nil && fixture.deliveries.isEmpty)
        #expect(fixture.minted == (race ? 2 : 0))
        #expect(try ModelContext(fixture.container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
    }

}
