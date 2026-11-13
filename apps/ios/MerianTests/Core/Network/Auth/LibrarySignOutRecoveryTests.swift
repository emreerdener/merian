import Foundation
@testable import Merian
import XCTest

@MainActor
final class LibrarySignOutRecoveryTests: XCTestCase {
    func testQualificationPreservesEveryInheritedSignOutPhase() async throws {
        for phase in [LibrarySignOutJournal.Phase.committed, .sourceCleared, .libraryCleared, .destinationCreated] {
            let harness = Harness()
            var journal = LibrarySignOutJournal(sourceUserID: harness.source)
            journal.phase = phase
            if phase == .destinationCreated { journal.destinationUserID = harness.destination }
            try harness.store.save(journal)
            let before = harness.data
            let session = harness.session
            let completed = await harness.coordinator.resume(preservePrimaryData: true)
            XCTAssertFalse(completed)
            XCTAssertEqual(harness.data, before)
            XCTAssertEqual(harness.session, session)
            XCTAssertEqual(harness.signOutCount, 0)
            XCTAssertEqual(harness.cleanupCount, 0)
            XCTAssertEqual(harness.createCount, 0)
        }
    }

    func testMissingSDKSnapshotStillRequiresVerifiedSignOut() async throws {
        let harness = Harness()
        try harness.commit()
        harness.session = nil
        harness.signOutSucceeds = false
        let completed = await harness.coordinator.resume()
        XCTAssertFalse(completed)
        XCTAssertEqual(harness.signOutCount, 1)
        XCTAssertEqual(harness.cleanupCount, 0)
        XCTAssertEqual(try harness.store.load()?.phase, .committed)
    }

    func testCleanupFailureBlocksGuestCreationAndRetainsJournal() async throws {
        let harness = Harness()
        try harness.commit()
        harness.cleanupSucceeds = false
        let completed = await harness.coordinator.resume()
        XCTAssertFalse(completed)
        XCTAssertNil(harness.session)
        XCTAssertEqual(harness.createCount, 0)
        XCTAssertEqual(try harness.store.load()?.phase, .sourceCleared)
        harness.cleanupSucceeds = true
        let retried = await harness.coordinator.resume()
        XCTAssertTrue(retried)
        XCTAssertEqual(harness.signOutCount, 1)
        XCTAssertNil(try harness.store.load())
    }

    func testSessionChangeDuringAsynchronousCleanupCannotAdvanceJournal() async throws {
        let harness = Harness()
        try harness.commit()
        harness.replaceSessionDuringCleanup = true
        let completed = await harness.coordinator.resume()
        XCTAssertFalse(completed)
        XCTAssertEqual(harness.cleanupCount, 1)
        XCTAssertEqual(harness.createCount, 0)
        XCTAssertEqual(try harness.store.load()?.phase, .sourceCleared)
    }

    func testLostLocalGuestJournalWriteReusesSDKDestination() async throws {
        let harness = Harness()
        try harness.commit()
        harness.rejectDestinationWrite = true
        let completed = await harness.coordinator.resume()
        XCTAssertFalse(completed)
        XCTAssertEqual(harness.createCount, 1)
        XCTAssertEqual(harness.session?.userID, harness.destination)
        XCTAssertEqual(try harness.store.load()?.phase, .libraryCleared)
        harness.rejectDestinationWrite = false
        let retried = await harness.coordinator.resume()
        XCTAssertTrue(retried)
        XCTAssertEqual(harness.createCount, 1)
    }

    func testPurchaseFailureReusesExactDestination() async throws {
        let harness = Harness()
        try harness.commit()
        harness.purchasesSucceed = false
        let completed = await harness.coordinator.resume()
        XCTAssertFalse(completed)
        XCTAssertEqual(try harness.store.load()?.destinationUserID, harness.destination)
        harness.purchasesSucceed = true
        let retried = await harness.coordinator.resume()
        XCTAssertTrue(retried)
        XCTAssertEqual(harness.createCount, 1)
        XCTAssertEqual(harness.cleanupCount, 1)
    }

    func testUnrelatedSDKIdentityCannotBeClearedOrAdopted() async throws {
        let harness = Harness()
        try harness.commit()
        harness.session = AuthTransitionSession(userID: UUID(), isAnonymous: false)
        let completed = await harness.coordinator.resume()
        XCTAssertFalse(completed)
        XCTAssertEqual(harness.signOutCount, 0)
        XCTAssertEqual(harness.cleanupCount, 0)
        XCTAssertEqual(harness.createCount, 0)
    }

    func testUnreadableJournalFailsClosed() async {
        let harness = Harness()
        harness.data = Data("invalid".utf8)
        let completed = await harness.coordinator.resume()
        XCTAssertFalse(completed)
        XCTAssertTrue(harness.store.isPending)
        XCTAssertEqual(harness.signOutCount, 0)
        XCTAssertEqual(harness.cleanupCount, 0)
    }

    func testLostServerOnlyGuestResponseCannotGuaranteeNoAdditionalGuests() async throws {
        let harness = Harness()
        try harness.commit()
        harness.loseCreationResponse = true
        let completed = await harness.coordinator.resume()
        XCTAssertFalse(completed)
        XCTAssertEqual(harness.createCount, 1)
        XCTAssertNil(harness.session)
        harness.loseCreationResponse = false
        let retried = await harness.coordinator.resume()
        XCTAssertTrue(retried)
        XCTAssertEqual(harness.createCount, 2)
    }

    func testJournalMutationDuringEveryAsyncBoundaryCannotAdvance() async throws {
        for boundary in ["signOut", "purge", "destination", "purchases"] {
            for mutation in ["source", "phase", "destination", "malformed", "remove"] {
                let harness = Harness()
                try harness.commit()
                harness.journalChangeAt = boundary
                harness.journalMutation = mutation
                let completed = await harness.coordinator.resume()
                XCTAssertFalse(completed, "Stale \(boundary) advanced")
                XCTAssertEqual(harness.data, harness.changedData, "Overwrote replacement at \(boundary)")
                if boundary == "signOut" { XCTAssertEqual(harness.cleanupCount, 0) }
                if boundary == "signOut" || boundary == "purge" { XCTAssertEqual(harness.createCount, 0) }
                XCTAssertEqual(harness.signOutJournals.map(\.phase), [.committed])
                if boundary != "signOut" { XCTAssertEqual(harness.purgeJournals.map(\.phase), [.sourceCleared]) }
            }
        }
    }

    func testRecoveryScopeBindsExactStepAndContextWithoutGrantingEarlyPurge() throws {
        let harness = Harness()
        try harness.commit()
        let committed = try XCTUnwrap(harness.store.load())
        var current = true
        let scope = try XCTUnwrap(harness.store.recoveryScope(expected: committed, validateContext: { current }))
        XCTAssertTrue(scope.isCurrent)
        XCTAssertFalse(scope.allowsLibraryPurge)
        current = false
        XCTAssertFalse(scope.isCurrent)
        current = true
        var journal = committed
        journal.phase = .sourceCleared
        try harness.store.save(journal)
        XCTAssertFalse(scope.isCurrent)
        let purge = try XCTUnwrap(harness.store.recoveryScope(expected: journal, validateContext: { current }))
        XCTAssertTrue(purge.allowsLibraryPurge)
        journal.phase = .libraryCleared
        try harness.store.save(journal)
        XCTAssertFalse(purge.allowsLibraryPurge)
        XCTAssertNil(harness.store.recoveryScope(expected: journal, validateContext: { true }))
        journal.phase = .destinationCreated; journal.destinationUserID = harness.destination
        try harness.store.save(journal)
        XCTAssertNil(harness.store.recoveryScope(expected: journal, validateContext: { true }))
        try harness.store.clear()
        XCTAssertFalse(scope.isCurrent)
        XCTAssertFalse(purge.isCurrent)
    }

    @MainActor private final class Harness {
        let source = UUID()
        let destination = UUID()
        var data: Data?
        var session: AuthTransitionSession?
        var signOutSucceeds = true
        var cleanupSucceeds = true
        var replaceSessionDuringCleanup = false
        var purchasesSucceed = true
        var rejectDestinationWrite = false
        var loseCreationResponse = false
        var journalChangeAt: String?
        var journalMutation = "source"
        var changedData: Data?
        var signOutJournals: [LibrarySignOutJournal] = []
        var purgeJournals: [LibrarySignOutJournal] = []
        var signOutCount = 0
        var cleanupCount = 0
        var createCount = 0

        init() { session = AuthTransitionSession(userID: source, isAnonymous: false) }

        var store: LibrarySignOutJournalStore {
            LibrarySignOutJournalStore(dependencies: .init(
                read: { self.data },
                write: { data in
                    if self.rejectDestinationWrite,
                       let record = try? JSONDecoder().decode(LibrarySignOutJournal.self, from: data),
                       record.phase == .destinationCreated { return false }
                    self.data = data
                    return true
                },
                remove: { self.data = nil }
            ))
        }

        func commit() throws { try store.save(LibrarySignOutJournal(sourceUserID: source)) }

        func changeJournal(at boundary: String) async {
            await Task.yield()
            guard journalChangeAt == boundary else { return }
            if journalMutation == "remove" { data = nil } else if journalMutation == "malformed" { data = Data("invalid".utf8) } else if journalMutation == "source" { data = try? JSONEncoder().encode(LibrarySignOutJournal(sourceUserID: UUID())) } else if var journal = try? store.load() {
                if journalMutation == "phase" {
                    journal.phase = journal.phase == .committed ? .sourceCleared : .committed
                    journal.destinationUserID = nil
                } else {
                    journal.phase = .destinationCreated
                    journal.destinationUserID = UUID()
                }
                data = try? JSONEncoder().encode(journal)
            }
            changedData = data
        }

        var coordinator: LibrarySignOutRecoveryCoordinator {
            LibrarySignOutRecoveryCoordinator(store: store, dependencies: .init(
                currentSession: { self.session },
                clearSourceSession: { journal in
                    self.signOutJournals.append(journal)
                    XCTAssertEqual(journal.sourceUserID, self.source)
                    await self.changeJournal(at: "signOut")
                    self.signOutCount += 1
                    if self.signOutSucceeds { self.session = nil }
                    return self.signOutSucceeds
                },
                clearLibrary: { journal in
                    self.purgeJournals.append(journal)
                    XCTAssertEqual(journal.sourceUserID, self.source)
                    await self.changeJournal(at: "purge")
                    self.cleanupCount += 1
                    await Task.yield()
                    if self.replaceSessionDuringCleanup {
                        self.session = AuthTransitionSession(userID: UUID(), isAnonymous: true)
                    }
                    return self.cleanupSucceeds
                },
                createDestination: {
                    await self.changeJournal(at: "destination")
                    self.createCount += 1
                    guard !self.loseCreationResponse else { return nil }
                    self.session = AuthTransitionSession(userID: self.destination, isAnonymous: true)
                    return self.session
                },
                completePurchases: { _ in
                    await self.changeJournal(at: "purchases")
                    return self.purchasesSucceed
                }
            ))
        }
    }
}
