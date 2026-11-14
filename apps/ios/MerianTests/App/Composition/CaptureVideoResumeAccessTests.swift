import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct CaptureVideoResumeAccessTests {
    @Test(arguments: ["ready", "held-consumed", "missing-source", "changed-frame", "account"])
    func originalPreviewVerifiesCohortWithoutAdmission(_ state: String) async throws {
        let current = MainActorTestValue(true)
        let fixture = ObservationVideoResumeStoreTests()
        let seed = try await fixture.seed(state == "held-consumed" ? state : "ready"); defer { seed.remove() }
        let before = try fixture.metadata(seed)
        var starts = 0, leases = 0
        var account = ObservationReanalysisProducerTests().account(finish: { leases -= 1 })
        account.begin = { owner in leases += 1; return .init(id: UUID(), session: .init(userID: owner, isAnonymous: false)) }
        let access = CaptureVideoResumeAccess.prepared(account: account, ownership: .init(),
            configuration: .init(start: { _, _, _, _, _ in starts += 1; return .started }),
            currentOwner: { seed.source.ownerID }, generation: { 1 }, sessionIsCurrent: { _ in current.value },
            containerIsCurrent: { $0 === seed.container }, documents: { seed.root })
        let read = try #require(try access.openResume(seed.preparation.identity, seed.container).preview)
        let original = seed.root.appendingPathComponent(seed.preparation.files[0].path)
        let expected = try Data(contentsOf: original)
        if state == "missing-source" { try FileManager.default.removeItem(at: original) }
        if state == "changed-frame" {
            let frame = seed.preparation.files[1]
            try Data(repeating: 0, count: frame.artifact.byteCount).write(to: seed.root.appendingPathComponent(frame.path))
        }
        if state == "account" { current.value = false }
        if ["missing-source", "changed-frame", "account"].contains(state) {
            await #expect(throws: (any Error).self) { try await read { true } }
        } else {
            let preview = try await read { true }
            #expect(preview.bytes == expected)
            try preview.validate(); current.value = false
            #expect(throws: (any Error).self) { try preview.validate() }
        }
        #expect(starts == 0 && leases == 0)
        #expect(try fixture.metadata(seed) == before)
    }

    @Test(arguments: ["staged", "reserved", "upload", "uploadReady", "idle", "running-consumed", "held-consumed", "unknown", "uploadUnknown", "running", "held"])
    func exactSavedRouteHandsOffOnlyAfterReaderLeaseExit(_ phase: String) async throws {
        let seed = try await ObservationVideoResumeStoreTests().seed(phase); defer { seed.remove() }
        var leases = 0, starts = 0
        let ownership = ObservationReanalysisPreparationOwner()
        var account = ObservationReanalysisProducerTests().account(finish: { leases -= 1 })
        account.begin = { owner in leases += 1; return .init(id: UUID(), session: .init(userID: owner, isAnonymous: false)) }
        let access = CaptureVideoResumeAccess.prepared(account: account, ownership: ownership,
            configuration: .init(start: { ready, session, generation, container, _ in
                starts += 1
                #expect(leases == 0 && !ownership.contains(seed.preparation.identity.analysisID))
                #expect(session.userID == seed.source.ownerID && generation == 19 && container === seed.container)
                #expect(ready.proof.preparation == seed.preparation)
                #expect(throws: Never.self) { try ObservationVideoResumeSubmission.validate(ready, container: container, isCurrent: { true }) }
                return .coalesced
            }), currentOwner: { seed.source.ownerID }, generation: { 19 }, sessionIsCurrent: { _ in true },
            containerIsCurrent: { $0 === seed.container }, documents: { seed.root })
        #expect(leases == 0 && starts == 0)
        let opened = try access.openResume(seed.preparation.identity, seed.container)
        #expect(leases == 0 && starts == 0)
        let held = ["unknown", "uploadUnknown", "running", "held"].contains(phase)
        #expect(try await opened.resume { true } == (held ? .unavailable : .coalesced))
        #expect(starts == (held ? 0 : 1) && leases == 0)
    }

    @Test(arguments: ["owner", "generation", "session", "container", "presentation"])
    func scopeLossCannotStageOrStart(_ change: String) async throws {
        let container = MainActorTestValue(true)
        let generation = MainActorTestValue(UInt64(1))
        let session = MainActorTestValue(true)
        let fixture = ObservationVideoResumeStoreTests(), seed = try await fixture.seed("ready")
        defer { seed.remove() }
        let before = try fixture.metadata(seed)
        var owner = seed.source.ownerID, starts = 0
        let access = CaptureVideoResumeAccess.prepared(account: ObservationReanalysisProducerTests().account(), ownership: .init(),
            configuration: .init(start: { _, _, _, _, _ in starts += 1; return .started }), currentOwner: { owner },
            generation: { generation.value }, sessionIsCurrent: { _ in session.value }, containerIsCurrent: { _ in container.value }, documents: { seed.root })
        let opened = try access.openResume(seed.preparation.identity, seed.container)
        switch change {
        case "owner": owner = UUID()
        case "generation": generation.value += 1
        case "session": session.value = false
        case "container": container.value = false
        default: break
        }
        await #expect(throws: (any Error).self) { try await opened.resume { change != "presentation" } }
        #expect(starts == 0)
        #expect(try fixture.metadata(seed) == before)
    }

    @Test func preparedCompositionPagesWithoutDispatchOrIdleLease() async throws {
        let seed = try await ObservationVideoResumeStoreTests().seed("staged"); defer { seed.remove() }
        var leases = 0, starts = 0
        var account = ObservationReanalysisProducerTests().account(finish: { leases -= 1 })
        account.begin = { id in leases += 1; return .init(id: UUID(), session: .init(userID: id, isAnonymous: false)) }
        let owner = ObservationAudioStatusOwner()
        let bundle = PreparedHistoryReanalysisComposition(routes: AppRouteCoordinator(), cloud: account,
            currentOwner: { seed.source.ownerID }, generation: { 1 }, sessionIsCurrent: { _ in true }, preparationOwner: .init(),
            enrollmentOwner: .init(), containerIsCurrent: { $0 === seed.container }, submitted: { _ in Issue.record("Photo admission") }, cleanup: {},
            audioStatusOwner: owner, video: .init(start: { _, _, _, _, _ in starts += 1; return .unavailable }), documents: { seed.root })
        #expect(leases == 0 && starts == 0 && owner.activeCount == 0)
        let status = try #require(bundle.videoStatus)
        let opened = try status.open(seed.source.ownerID, seed.source.observationID, seed.container)
        #expect(leases == 0 && starts == 0 && owner.activeCount == 0)
        let page = try await opened.page(nil, 20, { true })
        #expect(page.items == [.init(identity: seed.preparation.identity, phase: .reservationStaged)])
        #expect(leases == 0 && starts == 0 && owner.activeCount == 0)
        #expect(PreparedHistoryReanalysisComposition.appInstallation { bundle } == nil)
    }

    @Test func dismissalDuringReadPreservesStageButDoesNotDispatch() async throws {
        let seed = try await ObservationVideoResumeStoreTests().seed("staged"); defer { seed.remove() }
        var finishes = 0, presented = true, starts = 0
        let account = ObservationReanalysisProducerTests().account(finish: {
            finishes += 1
            if finishes == 2 { presented = false }
        })
        let access = CaptureVideoResumeAccess.prepared(account: account, ownership: .init(),
            configuration: .init(start: { _, _, _, _, _ in starts += 1; return .started }),
            currentOwner: { seed.source.ownerID }, generation: { 1 }, sessionIsCurrent: { _ in true },
            containerIsCurrent: { _ in true }, documents: { seed.root })
        let opened = try access.openResume(seed.preparation.identity, seed.container)
        await #expect(throws: (any Error).self) { try await opened.resume { presented } }
        #expect(starts == 0 && !presented)
        #expect(try ObservationVideoSourceReservationStore.read(proof: seed.proof, container: seed.container,
            isCurrent: { true }).work.phase == .staged)
    }
}
