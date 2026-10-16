import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct CaptureAudioSourceAccessTests {
    let fixture = ObservationAudioPreparationTests()

    @Test(arguments: [3, 4]) func freshHandoffIsStagedAndRetainsScope(_ sourceVersion: Int) async throws {
        let seed = try fixture.seed(sourceVersion: sourceVersion); defer { try? FileManager.default.removeItem(at: seed.root) }
        var leases = 0, starts = 0
        var account = fixture.fixture.account(finish: { leases -= 1 })
        account.begin = { owner in leases += 1; return .init(id: UUID(), session: .init(userID: owner, isAnonymous: false)) }
        let access = CaptureAudioSourceReanalysisAccess.prepared(account: account, ownership: .init(),
            configuration: .init(start: { _, _, _, _ in Issue.record("Fresh source used legacy execution"); return .unavailable },
                sourceStart: { key, proof, container, _ in
                    starts += 1
                    #expect(leases == 0 && key.session.userID == seed.source.ownerID && key.generation == 19)
                    #expect(key.container == ObjectIdentifier(seed.container) && container === seed.container)
                    #expect(key.snapshot.identity == proof.preparation.identity)
                    #expect((try? ObservationSourceReservationStore.read(key.snapshot.identity, container: container, isCurrent: { true })) == key.snapshot)
                    return .coalesced
                }), currentOwner: { seed.source.ownerID }, generation: { 19 }, sessionIsCurrent: { _ in true },
            containerIsCurrent: { $0 === seed.container }, documents: { seed.root })
        #expect(leases == 0 && starts == 0)
        let generation = UUID(), target = HistoricalReanalysisTarget(observationID: seed.source.observationID,
            analysisID: seed.source.analysisID, ownerID: seed.source.ownerID)
        let opened = try access.open(target, seed.container, generation)
        #expect(leases == 0)
        let plan = try opened.session.freeze([.audio(seed.bytes)], generation: generation)
        #expect(try await opened.submit { true } == .coalesced)
        try FileManager.default.removeItem(at: seed.root.appendingPathComponent(plan.verify().proof.preparation.path))
        #expect(try await opened.submit { true } == .coalesced)
        #expect(starts == 2 && leases == 0)
    }

    @Test(arguments: ["staged", "running", "unknown", "reserved", "held", "unavailable", "conflict"])
    func explicitSourceResumeUsesExactSavedState(_ state: String) async throws {
        let source = ObservationAudioSourceSubmissionTests(), seed = try await source.fixture.fixture.ready()
        defer { try? FileManager.default.removeItem(at: seed.root) }
        let saved = try source.state(state, seed: seed)
        try FileManager.default.removeItem(at: seed.file)
        var starts = 0
        let access = CaptureAudioSourceReanalysisAccess.prepared(account: fixture.fixture.account(), ownership: .init(),
            configuration: .init(start: { _, _, _, _ in Issue.record("Source resume used execution"); return .unavailable },
                sourceStart: { key, proof, _, _ in
                    starts += 1
                    #expect(key.snapshot == saved && proof.preparation == seed.preparation)
                    return .started
                }), currentOwner: { seed.source.ownerID }, generation: { 19 }, sessionIsCurrent: { _ in true },
            containerIsCurrent: { $0 === seed.container }, documents: { seed.root })
        let opened = try access.openSourceResume(saved.identity, seed.container)
        #expect(starts == 0)
        let result = try await opened.resume { true }
        #expect(result == (state == "conflict" ? .unavailable : .started))
        #expect(starts == (state == "conflict" ? 0 : 1))
    }

    @Test func repeatedFreshTapRoutesConsumedBindingOnlyToExecutionOwner() async throws {
        let seed = try fixture.seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        var sources = 0, executions = 0
        var expected: ObservationAudioExecutionStore.Snapshot?
        let access = CaptureAudioSourceReanalysisAccess.prepared(account: fixture.fixture.account(), ownership: .init(),
            configuration: .init(start: { key, _, _, _ in
                executions += 1; #expect(key.snapshot == expected); return .started
            }, sourceStart: { _, _, _, _ in sources += 1; return .unavailable }),
            currentOwner: { seed.source.ownerID }, generation: { 19 }, sessionIsCurrent: { _ in true },
            containerIsCurrent: { $0 === seed.container }, documents: { seed.root })
        let generation = UUID(), target = HistoricalReanalysisTarget(observationID: seed.source.observationID,
            analysisID: seed.source.analysisID, ownerID: seed.source.ownerID)
        let opened = try access.open(target, seed.container, generation)
        let plan = try opened.session.freeze([.audio(seed.bytes)], generation: generation), proof = try plan.verify().proof
        #expect(try await opened.submit { true } == .unavailable)
        let entry = try ObservationSourceReservationStore.read(proof.preparation.identity, container: seed.container, isCurrent: { true })
        let claim = try ObservationSourceReservationStore.claim(entry, admission: .initial, proof: .audio(proof), container: seed.container, isCurrent: { true })
        let reserved = try ObservationSourceReservationStore.settle(claim,
            reply: ObservationSourceStoreTests().reply(entry, state: "reserved"), proof: .audio(proof), container: seed.container, isCurrent: { true })
        let bound = try ObservationAudioExecutionStore.bindReserved(.init(reserved: reserved.work), source: reserved, proof: proof,
            authorization: ObservationAudioExecutionStoreTests().authorization, container: seed.container, isCurrent: { true })
        let execution = try ObservationAudioExecutionStore.claim(bound, purpose: .initial, proof: proof, container: seed.container, isCurrent: { true })
        expected = try ObservationAudioExecutionStore.consume(execution, proof: proof, container: seed.container, isCurrent: { true }).snapshot
        try FileManager.default.removeItem(at: seed.root.appendingPathComponent(proof.preparation.path))
        #expect(try await opened.submit { true } == .started)
        #expect(sources == 1 && executions == 1 && expected?.work.consumedAttempt == 1)
        #expect(throws: (any Error).self) {
            try ObservationAudioExecutionStore.claim(#require(expected), purpose: .initial, proof: proof, container: seed.container, isCurrent: { true })
        }
    }

    @Test(arguments: ["owner", "generation", "session", "container", "presentation"])
    func staleOpeningCannotSubmitOrResume(_ change: String) async throws {
        let source = ObservationAudioSourceSubmissionTests(), seed = try await source.fixture.fixture.ready()
        defer { try? FileManager.default.removeItem(at: seed.root) }
        let saved = try source.state("staged", seed: seed)
        var owner = seed.source.ownerID, generation: UInt64 = 1, session = true, container = true, starts = 0
        let access = CaptureAudioSourceReanalysisAccess.prepared(account: fixture.fixture.account(), ownership: .init(),
            configuration: .init(start: { _, _, _, _ in starts += 1; return .started }, sourceStart: { _, _, _, _ in starts += 1; return .started }),
            currentOwner: { owner }, generation: { generation }, sessionIsCurrent: { _ in session },
            containerIsCurrent: { _ in container }, documents: { seed.root })
        let presentation = UUID(), target = HistoricalReanalysisTarget(observationID: seed.source.observationID,
            analysisID: seed.source.analysisID, ownerID: seed.source.ownerID)
        let opened = try access.open(target, seed.container, presentation), resumed = try access.openSourceResume(saved.identity, seed.container)
        _ = try opened.session.freeze([.audio(seed.bytes)], generation: presentation)
        switch change {
        case "owner": owner = UUID()
        case "generation": generation += 1
        case "session": session = false
        case "container": container = false
        default: break
        }
        await #expect(throws: (any Error).self) { try await opened.submit { change != "presentation" } }
        await #expect(throws: (any Error).self) { try await resumed.resume { change != "presentation" } }
        #expect(starts == 0)
    }
}
