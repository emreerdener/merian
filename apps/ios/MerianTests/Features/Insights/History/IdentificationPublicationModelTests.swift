import Foundation
@testable import Merian
import SwiftData
import Testing
import UIKit

@MainActor @Suite(.serialized)
struct IdentificationPublicationModelTests {
    let fixture = ObservationPublicationConsentServiceTests()

    @Test func targetDiscoveryPrecedesPreflightAndSelectionPreservesExplicitOrder() async throws {
        let (container, snapshot) = try await fixture.seed(), ticket = try fixture.ticket(container)
        let continuation = bound(ticket, container), prepared = try await fixture.prepare(fixture.service(snapshot), container)
        var stages: [ObservationPublicationRequest] = [], calls: [String] = []
        let access = access(prepared, recover: { calls.append("target"); return .init(local: nil, remote: .absent) },
            prepare: { calls.append("prepare") }, stage: { stages.append($0.request) })
        let model = model(ticket, access, continuation)
        await model.prepare(); model.submit()
        #expect(calls.isEmpty && stages.isEmpty)
        await model.recover()
        #expect(calls == ["target"] && model.phase == .vacant && model.selected.isEmpty)
        await model.prepare()
        #expect(calls == ["target", "prepare"] && model.phase == .choosing && !model.canSubmit)
        let ids = snapshot.media.map(\.mediaID).reversed().map { $0 }
        for id in ids { model.toggle(id) }
        model.submit(); model.submit(); model.retrySave()
        #expect(stages.count == 1 && stages[0].mediaIDs == ids && stages[0].note == nil)
        #expect(model.phase == .submitted && continuation.held == nil)
    }

    @Test(arguments: ["local", "remote", "error"])
    func occupiedOrUncertainNeverPreflightsOrMints(_ mode: String) async throws {
        let (container, snapshot) = try await fixture.seed(), ticket = try fixture.ticket(container)
        let prepared = try await fixture.prepare(fixture.service(snapshot), container)
        let remote = try receipt(ticket), local = ObservationPublicationOperationStatus(operationID: UUID(), analysisID: UUID(), phase: .needsAttention)
        let access = access(prepared, recover: {
            if mode == "error" { throw ObservationHistoryError.unavailable }
            return .init(local: mode == "local" ? local : nil, remote: mode == "remote" ? .found(remote) : .absent)
        }, prepare: { Issue.record("Occupied work cannot prepare") }, stage: { _ in Issue.record("No new operation") })
        let model = model(ticket, access, bound(ticket, container))
        await model.recover(); await model.prepare(); model.toggle(fixture.secondPhoto); model.submit()
        #expect(!model.canSubmit && model.phase != .vacant)
    }

    @Test func nullAfterUncertaintyCannotReopenConsent() async throws {
        let (container, snapshot) = try await fixture.seed(), ticket = try fixture.ticket(container)
        let prepared = try await fixture.prepare(fixture.service(snapshot), container)
        var fail = true
        let access = access(prepared, recover: {
            if fail { throw ObservationHistoryError.unavailable }
            return .init(local: nil, remote: .absent)
        }, prepare: { Issue.record("Uncertainty must remain blocked") })
        let model = model(ticket, access, bound(ticket, container))
        await model.recover(); fail = false; await model.recover(); await model.prepare()
        #expect(model.phase == .uncertain)
    }

    @Test(arguments: [false, true])
    func ambiguousSaveSurvivesDismissalAndRevisionChange(commitFirst: Bool) async throws {
        let (container, snapshot) = try await fixture.seed(), ticket = try fixture.ticket(container)
        let continuation = bound(ticket, container)
        var service = fixture.service(snapshot), wakes = 0
        service.wake = { wakes += 1 }
        let prepared = try await fixture.prepare(service, container)
        service.save = { context in
            if commitFirst { try context.save() }
            throw ObservationHistoryError.unavailable
        }
        var access = access(prepared, stage: { try service.stage($0, container: container, isCurrent: { true }) })
        let first = model(ticket, access, continuation)
        await first.recover(); await first.prepare(); first.toggle(fixture.secondPhoto); first.submit()
        let held = try #require(continuation.held)
        #expect(wakes == 0 && first.canRetrySave)
        first.close()
        try fixture.advanceTarget(container)
        let newer = try fixture.ticket(container)
        continuation.bind(owner: newer.ownerID, observation: newer.observationID, container: container)
        service.save = { try $0.save() }
        access.prepare = { _ in Issue.record("Held request cannot prepare again"); return prepared }
        access.stage = { try service.stage($0, container: container, isCurrent: { true }) }
        let reopened = model(newer, access, continuation)
        await reopened.recover(); await reopened.prepare(); reopened.retrySave()
        if commitFirst {
            #expect(continuation.held == nil && reopened.phase == .submitted && wakes == 1)
        } else {
            #expect(continuation.held?.acceptance.request.operationID == held.acceptance.request.operationID && wakes == 0)
        }
        let saved = try ObservationPublicationOperationStatus.readTarget(ownerID: ticket.ownerID, observationID: ticket.observationID,
            container: container, isCurrent: { true })
        #expect(saved?.operationID == (commitFirst ? held.acceptance.request.operationID : nil))
    }

    @Test func closingOrAccountLossWithholdsLateResultsAndClearsPhoto() async throws {
        let (container, snapshot) = try await fixture.seed(), ticket = try fixture.ticket(container)
        let prepared = try await fixture.prepare(fixture.service(snapshot), container)
        var current = true
        let access = access(prepared, recover: { current = false; return .init(local: nil, remote: .absent) })
        let model = IdentificationPublicationModel(ticket: ticket, access: access, continuation: bound(ticket, container),
            isCurrent: { current }, photo: { _, _ in Issue.record("No private image read"); return UIImage() })
        await model.recover(); await model.prepare()
        #expect(model.phase == .closed && model.candidates.isEmpty)
    }

    @Test func photosRequireExactCandidateAndStaleResultIsWithheld() async throws {
        let (container, snapshot) = try await fixture.seed(), ticket = try fixture.ticket(container)
        let prepared = try await fixture.prepare(fixture.service(snapshot), container), continuation = bound(ticket, container)
        var calls = 0, current = true
        let model = IdentificationPublicationModel(ticket: ticket, access: access(prepared), continuation: continuation,
            isCurrent: { current }, photo: { analysis, media in
                calls += 1; #expect(analysis == ticket.analysisID && media == fixture.secondPhoto)
                current = false; return UIImage()
            })
        await model.recover(); await model.prepare()
        await model.previewPhoto(UUID()); #expect(calls == 0)
        await model.previewPhoto(fixture.secondPhoto)
        #expect(calls == 1 && model.photo == nil && model.phase == .closed)
    }

    @Test(arguments: [false, true])
    func sharedChoosingModelsCannotMintASecondRequest(firstSaveFails: Bool) async throws {
        let (container, snapshot) = try await fixture.seed(), ticket = try fixture.ticket(container)
        let prepared = try await fixture.prepare(fixture.service(snapshot), container), continuation = bound(ticket, container)
        var requests: [ObservationPublicationRequest] = []
        let access = access(prepared, stage: {
            requests.append($0.request)
            if firstSaveFails { throw ObservationHistoryError.unavailable }
        })
        let first = model(ticket, access, continuation), second = model(ticket, access, continuation)
        await first.recover(); await first.prepare(); await second.recover(); await second.prepare()
        first.toggle(fixture.secondPhoto); second.toggle(fixture.secondPhoto)
        first.submit(); second.submit()
        #expect(requests.count == 1 && continuation.isOccupied && !second.canSubmit)
        continuation.bind(owner: ticket.ownerID, observation: ticket.observationID, container: container)
        #expect(continuation.isOccupied)
        if firstSaveFails {
            first.retrySave()
            #expect(requests.count == 2 && requests[0].operationID == requests[1].operationID)
        } else { #expect(continuation.held == nil && continuation.settledOperation == requests[0].operationID) }
    }

    @Test func parentScopePreservesHeldAcrossOtherObservationButClearsOnAccountOrContainerChange() async throws {
        let (container, snapshot) = try await fixture.seed(), ticket = try fixture.ticket(container)
        let prepared = try await fixture.prepare(fixture.service(snapshot), container), continuation = bound(ticket, container)
        let accepted = try prepared.accepting(mediaIDs: [fixture.secondPhoto])
        try continuation.retain(accepted, ticket: ticket)
        continuation.bind(owner: ticket.ownerID, observation: UUID(), container: container)
        #expect(continuation.matches(ticket) && continuation.held?.acceptance.request.operationID == accepted.request.operationID)
        continuation.bind(owner: UUID(), observation: ticket.observationID, container: container)
        #expect(continuation.held == nil && !continuation.matches(ticket))
        continuation.bind(owner: ticket.ownerID, observation: ticket.observationID, container: container)
        try continuation.retain(accepted, ticket: ticket)
        continuation.bind(owner: ticket.ownerID, observation: ticket.observationID, container: NSObject())
        #expect(!continuation.isOccupied)
        continuation.clear(); #expect(!continuation.matches(ticket))
    }

    @Test func cancellingOldPhotoDoesNotCloseChooserOrEraseNewPreview() async throws {
        let (container, snapshot) = try await fixture.seed(), ticket = try fixture.ticket(container)
        let prepared = try await fixture.prepare(fixture.service(snapshot), container)
        let entered = AsyncStream<Void>.makeStream()
        var release: CheckedContinuation<Void, Never>?
        defer { release?.resume(); entered.continuation.finish() }
        let firstID = try #require(snapshot.media.first?.mediaID), image = UIImage()
        let model = IdentificationPublicationModel(ticket: ticket, access: access(prepared), continuation: bound(ticket, container),
            isCurrent: { true }, photo: { _, media in
                if media == firstID { await withCheckedContinuation { release = $0; entered.continuation.yield() } }
                return image
            })
        await model.recover(); await model.prepare()
        let first = Task { await model.previewPhoto(firstID) }
        for await _ in entered.stream { break }
        first.cancel()
        await model.previewPhoto(fixture.secondPhoto)
        let continuation = release; release = nil; continuation?.resume(); await first.value
        #expect(model.phase == .choosing && model.photoID == fixture.secondPhoto && model.photo === image)
    }

    @Test(arguments: [false, true])
    func cancelledChecksLeaveNoSpinnerOrPermission(preflight: Bool) async throws {
        let (container, snapshot) = try await fixture.seed(), ticket = try fixture.ticket(container)
        let prepared = try await fixture.prepare(fixture.service(snapshot), container)
        let entered = AsyncStream<Void>.makeStream()
        var release: CheckedContinuation<Void, Never>?
        defer { release?.resume(); entered.continuation.finish() }
        let wait = { @MainActor in await withCheckedContinuation { release = $0; entered.continuation.yield() } }
        var access = access(prepared, recover: {
            if !preflight { await wait() }
            return .init(local: nil, remote: .absent)
        })
        access.prepare = { _ in await wait(); return prepared }
        let model = model(ticket, access, bound(ticket, container))
        if preflight { await model.recover() }
        let task = Task { if preflight { await model.prepare() } else { await model.recover() } }
        for await _ in entered.stream { break }
        task.cancel(); let continuation = release; release = nil; continuation?.resume(); await task.value
        #expect(model.phase == .uncertain && !model.isBusy && !model.canSubmit && model.candidates.isEmpty)
    }

    @Test func allCandidatesRemainVisibleButOnlySixExplicitChoicesAreAccepted() async throws {
        let (container, original) = try await fixture.seed(), ticket = try fixture.ticket(container)
        let ids = (0..<8).map { _ in UUID() }, reference = try #require(original.media.first)
        let row: [String: Any] = ["schema_version": 1, "observation_id": ticket.observationID.uuidString.lowercased(),
            "analysis_id": ticket.analysisID.uuidString.lowercased(), "expected_observation_revision": ticket.observationRevision,
            "expected_review_revision": ticket.reviewRevision, "taxonomy_version_id": original.taxonomyVersionID.uuidString.lowercased(),
            "initial_taxon_id": NSNull(), "media": ids.map {
                ["media_id": $0.uuidString.lowercased(), "content_type": reference.contentType,
                 "byte_count": reference.byteCount, "sha256": reference.sha256] as [String: Any]
            }]
        let snapshot = try ObservationPublicationConsentSnapshot.decode(JSONSerialization.data(withJSONObject: row),
            request: .init(observationID: ticket.observationID, analysisID: ticket.analysisID))
        let prepared = try await fixture.prepare(fixture.service(snapshot), container)
        let model = model(ticket, access(prepared), bound(ticket, container))
        await model.recover(); await model.prepare()
        #expect(model.candidates.map(\.mediaID) == ids && model.selected.isEmpty)
        for id in ids.reversed() { model.toggle(id) }
        #expect(model.selected == Array(ids.reversed().prefix(6)))
        model.toggle(ids[7]); model.toggle(ids[0])
        #expect(model.selected.last == ids[0] && model.selected.count == 6)
    }

    private func bound(_ ticket: ObservationAnalysisReviewTicket, _ container: ModelContainer) -> PublicationConsentContinuation {
        let continuation = PublicationConsentContinuation()
        continuation.bind(owner: ticket.ownerID, observation: ticket.observationID, container: container)
        return continuation
    }
    private func model(_ ticket: ObservationAnalysisReviewTicket, _ access: IdentificationHistoryPublicationAccess,
                       _ continuation: PublicationConsentContinuation) -> IdentificationPublicationModel {
        .init(ticket: ticket, access: access, continuation: continuation, isCurrent: { true }, photo: { _, _ in UIImage() })
    }
    private func access(_ prepared: ObservationPublicationConsentService.Prepared,
                        recover: @escaping () async throws -> ObservationPublicationTargetRecovery = { .init(local: nil, remote: .absent) },
                        prepare: @escaping () throws -> Void = {},
                        stage: @escaping (ObservationPublicationConsentService.Acceptance) throws -> Void = { _ in }) -> IdentificationHistoryPublicationAccess {
        .init(prepare: { _ in try prepare(); return prepared }, stage: stage, status: { _, _ in nil },
            recoverTarget: { _ in try await recover() }, generation: { 0 })
    }
    private func receipt(_ ticket: ObservationAnalysisReviewTicket) throws -> ObservationPublicationReceipt {
        let request = ObservationPublicationStatusRequest(operationID: UUID(), observationID: ticket.observationID, analysisID: UUID())
        return try .decodeStatus(JSONSerialization.data(withJSONObject: ["schema_version": 1,
            "operation_id": request.operationID.uuidString.lowercased(), "observation_id": request.observationID.uuidString.lowercased(),
            "analysis_id": request.analysisID.uuidString.lowercased(), "status": "needs_action"]), request: request)
    }
}
