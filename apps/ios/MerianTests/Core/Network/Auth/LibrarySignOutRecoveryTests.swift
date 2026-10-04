import Foundation
@testable import Merian
import XCTest

@MainActor
final class LibrarySignOutRecoveryTests: XCTestCase {
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

    @MainActor private final class Harness {
        let source = UUID()
        let destination = UUID()
        var data: Data?
        var session: AuthTransitionSession?
        var signOutSucceeds = true
        var cleanupSucceeds = true
        var purchasesSucceed = true
        var rejectDestinationWrite = false
        var loseCreationResponse = false
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

        var coordinator: LibrarySignOutRecoveryCoordinator {
            LibrarySignOutRecoveryCoordinator(store: store, dependencies: .init(
                currentSession: { self.session },
                clearSourceSession: {
                    self.signOutCount += 1
                    if self.signOutSucceeds { self.session = nil }
                    return self.signOutSucceeds
                },
                clearLibrary: {
                    self.cleanupCount += 1
                    return self.cleanupSucceeds
                },
                createDestination: {
                    self.createCount += 1
                    guard !self.loseCreationResponse else { return nil }
                    self.session = AuthTransitionSession(userID: self.destination, isAnonymous: true)
                    return self.session
                },
                completePurchases: { _ in self.purchasesSucceed }
            ))
        }
    }
}
