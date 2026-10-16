import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct CaptureAudioStatusAccessTests {
    let fixture = ObservationAudioPreparationTests()

    @Test func inertAssemblyAndOpeningHaveNoIdleLeaseOrExecution() async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        _ = try fixture.phase(seed)
        var leases = 0
        var account = fixture.fixture.account(finish: { leases -= 1 })
        account.begin = { id in leases += 1; return .init(id: UUID(), session: .init(userID: id, isAnonymous: false)) }
        let owner = ObservationAudioStatusOwner()
        let bundle = PreparedHistoryReanalysisComposition(routes: AppRouteCoordinator(), cloud: account,
            currentOwner: { seed.source.ownerID }, generation: { 7 }, sessionIsCurrent: { _ in true },
            preparationOwner: .init(), enrollmentOwner: .init(), containerIsCurrent: { $0 === seed.container },
            submitted: { _ in Issue.record("Status submitted work") }, cleanup: { Issue.record("Status erased work") }, audioStatusOwner: owner)
        #expect(leases == 0 && owner.activeCount == 0)
        let access = try #require(bundle.audioStatus)
        let opened = try access.open(seed.source.ownerID, seed.source.observationID, seed.container)
        #expect(leases == 0 && owner.activeCount == 0)
        let page = try await opened.page(nil, 20, { true })
        #expect(page.items.count == 1 && page.items.first?.identity == seed.preparation.identity)
        #expect(leases == 0 && owner.activeCount == 0)
        #expect(PreparedHistoryReanalysisComposition.prepared(in: .preview).audioStatus != nil)
        #expect(PreparedHistoryReanalysisComposition.appInstallation { bundle } == nil)
    }

    @Test(arguments: ["owner", "generation", "session", "container", "presentation"])
    func scopeLossAfterOpenWithholdsPage(_ change: String) async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        _ = try fixture.phase(seed)
        var currentOwner = seed.source.ownerID, generation: UInt64 = 1, session = true, container = true, reads = 0
        let access = CaptureAudioStatusAccess.prepared(account: fixture.fixture.account(), owner: .init(),
            reader: .init(read: { _, _, _ in reads += 1; throw MerianError.invalidResponse }), currentOwner: { currentOwner },
            generation: { generation }, sessionIsCurrent: { _ in session }, containerIsCurrent: { _ in container })
        let opened = try access.open(seed.source.ownerID, seed.source.observationID, seed.container)
        switch change {
        case "owner": currentOwner = UUID()
        case "generation": generation += 1
        case "session": session = false
        case "container": container = false
        default: break
        }
        await #expect(throws: (any Error).self) { try await opened.page(nil, 20, { change != "presentation" }) }
        #expect(reads == 0)
    }

    @Test(arguments: ["account", "presentation", "deletion"])
    func lossDuringReadNeverPublishesPrivatePage(_ change: String) async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        _ = try fixture.phase(seed)
        var current = true, presentation = true, finishes = 0
        let account = fixture.fixture.account(finish: { finishes += 1 })
        let reader = ObservationAudioSavedStatus(read: { identity, container, validate in
            let saved = try await ObservationAudioResumeStore.read(identity, container: container, isCurrent: validate)
            switch change {
            case "account": current = false
            case "presentation": presentation = false
            default:
                let context = ModelContext(container)
                let scan = try ObservationHistorySyncService.enrolledScan(seed.source.observationID.uuidString.lowercased(), context: context)
                context.delete(scan); try context.save()
            }
            return saved
        })
        let access = CaptureAudioStatusAccess.prepared(account: account, owner: .init(), reader: reader,
            currentOwner: { seed.source.ownerID }, generation: { 1 }, sessionIsCurrent: { _ in current }, containerIsCurrent: { _ in true })
        let opened = try access.open(seed.source.ownerID, seed.source.observationID, seed.container)
        await #expect(throws: (any Error).self) { try await opened.page(nil, 20, { presentation }) }
        #expect(finishes == 2)
    }

    @Test func missingParentAndWrongOwnerFailBeforePresentation() throws {
        let seed = try fixture.seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let access = CaptureAudioStatusAccess.prepared(account: fixture.fixture.account(), owner: .init(), reader: .init(),
            currentOwner: { seed.source.ownerID }, generation: { 1 }, sessionIsCurrent: { _ in true }, containerIsCurrent: { _ in true })
        #expect(throws: (any Error).self) { try access.open(UUID(), seed.source.observationID, seed.container) }
        #expect(throws: (any Error).self) { try access.open(seed.source.ownerID, UUID(), seed.container) }
    }
}
