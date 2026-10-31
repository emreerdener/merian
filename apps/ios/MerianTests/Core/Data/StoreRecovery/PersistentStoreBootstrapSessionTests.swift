import Foundation
@testable import Merian
import SwiftData
import XCTest

@MainActor
final class PersistentStoreBootstrapSessionTests: XCTestCase {
    func testRetainedAdmissionReacquiresExactFenceAfterStartupSessionEnds() throws {
        let root = try temporaryRoot()
        let outcome = ModelContainerBootstrapper.fixtureBootstrap { try self.fixture(root) }
        let container = try XCTUnwrap(outcome.container)
        let admission = try XCTUnwrap(outcome.nativeReleaseAdmission)
        let fence = try admission.acquireFence(container: container)
        try admission.require(container: container, fence: fence)
        XCTAssertThrowsError(try admission.acquireFence(container: container))
        let other = try ModelContainerFactory.makeInMemoryContainer()
        XCTAssertThrowsError(try admission.acquireFence(container: other))
        try admission.require(container: container, fence: fence)
    }

    func testRetainedAdmissionNeverRecreatesMissingFence() throws {
        let root = try temporaryRoot()
        let outcome = ModelContainerBootstrapper.fixtureBootstrap { try self.fixture(root) }
        let container = try XCTUnwrap(outcome.container)
        let admission = try XCTUnwrap(outcome.nativeReleaseAdmission)
        let configuration = try XCTUnwrap(container.configurations.first)
        let fenceURL = configuration.url.deletingLastPathComponent()
            .appendingPathComponent(SharedMediaStoreReadFence.name)
        try FileManager.default.removeItem(at: fenceURL)
        XCTAssertThrowsError(try admission.acquireFence(container: container))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fenceURL.path))
    }

    func testRetainedAdmissionRejectsReplacementFenceWithoutAdoptingIt() throws {
        let root = try temporaryRoot()
        let outcome = ModelContainerBootstrapper.fixtureBootstrap { try self.fixture(root) }
        let container = try XCTUnwrap(outcome.container)
        let admission = try XCTUnwrap(outcome.nativeReleaseAdmission)
        let configuration = try XCTUnwrap(container.configurations.first)
        let fenceURL = configuration.url.deletingLastPathComponent()
            .appendingPathComponent(SharedMediaStoreReadFence.name)
        // Keep the old inode alive at another fixture name, preventing inode reuse.
        try FileManager.default.moveItem(at: fenceURL,
            to: fenceURL.appendingPathExtension("retained-original"))
        var replacement: SharedMediaStoreReadFence? = try SharedMediaStoreReadFence(
            store: configuration.url, access: .sharedWriter)
        let replacementBinding = try XCTUnwrap(replacement).binding()
        replacement = nil
        XCTAssertThrowsError(try admission.acquireFence(container: container))
        let reopened = try SharedMediaStoreReadFence(store: configuration.url,
            access: .sharedWriter, requireExisting: true)
        XCTAssertEqual(try reopened.binding(), replacementBinding)
    }

    func testFirstSuccessfulOpenBindsAdmissionToExactContainerAndFence() throws {
        let root = try temporaryRoot()
        let session = try fixture(root)
        let outcome = ModelContainerBootstrapper.fixtureBootstrap { session }
        let container = try XCTUnwrap(outcome.container)
        let admission = try XCTUnwrap(outcome.nativeReleaseAdmission)
        XCTAssertEqual(outcome.startupStoreState, .normal)
        XCTAssertEqual(session.attempts, 1)
        XCTAssertEqual(container.configurations.first, session.configuration)
        try admission.require(container: container, fence: session.fence)
        let other = try ModelContainerFactory.makeInMemoryContainer()
        XCTAssertThrowsError(try admission.require(container: other, fence: session.fence))
        XCTAssertThrowsError(try SharedMediaStoreReadFence(store: session.storeURL, access: .sharedWriter))
        // A later constructor on this session cannot recreate eligibility.
        _ = try session.construct { container }
        XCTAssertNil(try session.admission(for: container))
        XCTAssertThrowsError(try admission.require(container: container, fence: session.fence))
        XCTAssertThrowsError(try admission.acquireFence(container: container))
    }

    func testWrongConfigurationInvalidatesSessionBeforeAnotherAttempt() throws {
        let root = try temporaryRoot()
        let session = try fixture(root)
        let wrong = try ModelContainerFactory.makeInMemoryContainer()
        XCTAssertThrowsError(try session.construct { wrong })
        XCTAssertThrowsError(try session.admission(for: wrong))
        XCTAssertThrowsError(try session.construct { wrong })
        XCTAssertEqual(session.attempts, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.storeURL.path))
    }

    func testRecoveryBoundaryFailureCannotResumePersistentConstruction() throws {
        let root = try temporaryRoot()
        let session = try fixture(root)
        XCTAssertThrowsError(try session.recover {
            throw StoreBootstrapBoundaryFailure.indeterminateConstruction
        })
        XCTAssertThrowsError(try session.construct { try ModelContainerFactory.makeInMemoryContainer() })
        XCTAssertEqual(session.attempts, 0)
    }

    func testChecksumRetryKeepsExactConfigurationButDeniesNewWriterEligibility() throws {
        let root = try temporaryRoot()
        var observed = [Int]()
        let session = try fixture(root) { attempt in
            observed.append(attempt)
            if attempt == 1 {
                throw NSError(domain: "app.merian.model-container", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Duplicate version checksums across stages detected."
                ])
            }
        }
        let outcome = ModelContainerBootstrapper.fixtureBootstrap { session }
        let container = try XCTUnwrap(outcome.container)
        XCTAssertEqual(observed, [1, 2])
        XCTAssertEqual(outcome.startupStoreState, .normal)
        XCTAssertEqual(container.configurations.first, session.configuration)
        XCTAssertNil(outcome.nativeReleaseAdmission)
        XCTAssertNil(try session.admission(for: container))
        // Denial is construction provenance, not a ban on ordinary reads.
        let context = ModelContext(container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SharedMediaReceivingIntentRecord>()), 0)
    }

    func testKnownSwiftFailureDoesNotArchiveCurrentStoreOrGrantAdmission() throws {
        let root = try temporaryRoot()
        let session = try fixture(root) { _ in throw Stub.ordinary }
        let outcome = ModelContainerBootstrapper.fixtureBootstrap { session }
        XCTAssertEqual(outcome.startupStoreState, .safeMode)
        XCTAssertNil(outcome.nativeReleaseAdmission)
        XCTAssertEqual(session.attempts, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("store-quarantine").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("store-rescue").path))
    }

    func testIndeterminateBridgeAndMissingContainerNeverRetryOrArchive() throws {
        for missing in [false, true] {
            let root = try temporaryRoot()
            let session = try fixture(root) { _ in
                if missing {
                    _ = try ModelContainerFactory.completedConstruction(
                        container: nil, swiftError: nil, exceptionError: nil
                    )
                } else {
                    _ = try ModelContainerFactory.makeContainerCatchingObjectiveCExceptions {
                        NSException(name: .genericException, reason: "Synthetic startup exception", userInfo: nil).raise()
                        throw Stub.ordinary
                    }
                }
            }
            let outcome = ModelContainerBootstrapper.fixtureBootstrap { session }
            XCTAssertEqual(outcome.startupStoreState, .safeMode)
            XCTAssertNil(outcome.nativeReleaseAdmission)
            XCTAssertEqual(session.attempts, 1)
            XCTAssertFalse(FileManager.default.fileExists(atPath: session.storeURL.path))
            XCTAssertThrowsError(try session.construct { try ModelContainerFactory.makeInMemoryContainer() })
            XCTAssertEqual(session.attempts, 1)
        }
    }

    func testQuarantineReplacementHoldsFenceAndKeepsAdmissionDenied() throws {
        let root = try temporaryRoot()
        let store = root.appendingPathComponent("default.store")
        let original = Data("Synthetic corrupt store".utf8)
        try original.write(to: store)
        var attempts = [Int]()
        let session = try fixture(root) { attempt in
            attempts.append(attempt)
            XCTAssertThrowsError(try SharedMediaStoreReadFence(store: store, access: .sharedWriter))
            if attempt == 1 { throw StoreRecoveryTestSupport.sqliteCorruptionError() }
        }
        let outcome = ModelContainerBootstrapper.fixtureBootstrap { session }
        XCTAssertEqual(attempts, [1, 2])
        XCTAssertEqual(outcome.startupStoreState, .recovered)
        XCTAssertNotNil(outcome.container)
        XCTAssertNil(outcome.nativeReleaseAdmission)
        let archives = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("store-quarantine"), includingPropertiesForKeys: nil
        )
        XCTAssertEqual(archives.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(archives.first).appendingPathComponent("default.store")), original)
        try session.check()
    }

    func testLegacyRescueReplacementHoldsFenceAndKeepsAdmissionDenied() throws {
        try legacyRescueReplacement(schema: MerianSchemaV65.self, source: .v65)
        try legacyRescueReplacement(schema: MerianSchemaV66.self, source: .v66)
        try legacyRescueReplacement(schema: MerianSchemaV67.self, source: .v67)
    }

    private func legacyRescueReplacement(schema: any VersionedSchema.Type,
                                        source: ModelStoreRecoveryCoordinator.RecentSourceSchema) throws {
        let root = try temporaryRoot()
        let store = root.appendingPathComponent("default.store")
        try autoreleasepool {
            let legacy = Schema(versionedSchema: schema)
            _ = try ModelContainerFactory.makeContainerCatchingObjectiveCExceptions {
                try ModelContainer(for: legacy, configurations: [
                    ModelConfiguration(schema: legacy, url: store, cloudKitDatabase: .none)
                ])
            }
        }
        let decision = ModelStoreRecoveryCoordinator.migrationDecision(
            at: store, currentSchemaMajor: CurrentSchema.versionIdentifier.major
        )
        XCTAssertEqual(decision.hint, .recentSource(source))
        let original = try Data(contentsOf: store)
        var attempts = [Int]()
        let session = try fixture(root) { attempt in
            attempts.append(attempt)
            XCTAssertThrowsError(try SharedMediaStoreReadFence(store: store, access: .sharedWriter))
            if attempt == 1 {
                throw NSError(domain: "SwiftData.SwiftDataError", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Synthetic legacy migration failure"])
            }
        }
        let outcome = ModelContainerBootstrapper.fixtureBootstrap { session }
        XCTAssertEqual(attempts, [1, 2])
        XCTAssertEqual(outcome.startupStoreState, .recovered)
        XCTAssertEqual(outcome.telemetryEvent?.reason, "legacy_store_rescued")
        XCTAssertEqual(try XCTUnwrap(outcome.container).configurations.first, session.configuration)
        XCTAssertNil(outcome.nativeReleaseAdmission)
        let archives = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("store-rescue"), includingPropertiesForKeys: nil
        )
        XCTAssertEqual(archives.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(archives.first).appendingPathComponent("default.store")), original)
        try session.check()
    }

    func testReplacedFenceCannotReachConstructionOrArchive() throws {
        let root = try temporaryRoot()
        let session = try fixture(root)
        let control = root.appendingPathComponent(SharedMediaStoreReadFence.name)
        try FileManager.default.moveItem(at: control, to: root.appendingPathComponent("retained-fence"))
        try Data().write(to: control)
        let outcome = ModelContainerBootstrapper.fixtureBootstrap { session }
        XCTAssertEqual(outcome.startupStoreState, .safeMode)
        XCTAssertNil(outcome.nativeReleaseAdmission)
        XCTAssertEqual(session.attempts, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.storeURL.path))
    }

    func testTestModeNeverResolvesPersistentSession() throws {
        var reached = false
        let outcome = ModelContainerBootstrapper.fixtureBootstrap(isTesting: true) {
            reached = true
            throw Stub.ordinary
        }
        XCTAssertFalse(reached)
        XCTAssertEqual(outcome.startupStoreState, .normal)
        XCTAssertTrue(try XCTUnwrap(outcome.container?.configurations.first).isStoredInMemoryOnly)
        XCTAssertNil(outcome.nativeReleaseAdmission)
    }

    func testExplicitCloudKitDisablementPreservesAutomaticGroupPlacement() {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let prior = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false,
                                       groupContainer: .automatic, cloudKitDatabase: .automatic)
        let current = ModelStoreRecoveryCoordinator.productionStoreConfiguration(for: schema)
        let expected = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false,
                                          groupContainer: .automatic, cloudKitDatabase: .none)
        XCTAssertEqual(current, expected)
        XCTAssertEqual(current.url, prior.url)
        XCTAssertEqual(current.groupAppContainerIdentifier, prior.groupAppContainerIdentifier)
        XCTAssertNil(current.cloudKitContainerIdentifier)
    }

    func testDeniedRetryCanRecoverReceivedP2AndLaterCleanOpenCanQualify() async throws {
        let (store, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(receiving: true)
        let checks = SharedMediaNativeReceivingStagingTests()
        let prepared = try await owner.stageAppReceiving(
            packageID: store.packageID, draftGeneration: store.draft, pairIDs: checks.pairIDs(request)
        )
        let received = try await owner.receiveAppPrepared(prepared)
        let invalidated = await owner.invalidateAndAwaitForAccountTransition()
        XCTAssertTrue(invalidated)
        let url = try XCTUnwrap(store.container.configurations.first).url
        func open(retry: Bool) throws -> ModelContainerBootstrapOutcome {
            let session = try PersistentStoreBootstrapSession.fixture(
                schema: Schema(versionedSchema: CurrentSchema.self), storeURL: url,
                anchor: url.deletingLastPathComponent(), beforeAttempt: { attempt in
                    if retry && attempt == 1 {
                        throw NSError(domain: "app.merian.model-container", code: 2, userInfo: [
                            NSLocalizedDescriptionKey: "Duplicate version checksums across stages detected."
                        ])
                    }
                }
            )
            return ModelContainerBootstrapper.fixtureBootstrap { session }
        }
        let denied = try open(retry: true)
        XCTAssertNil(denied.nativeReleaseAdmission)
        let cold = try await checks.reopen(store, container: XCTUnwrap(denied.container))
        try cold.setMetadataFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.closed } }
        let recovered = try await cold.receiveAppPrepared(prepared)
        XCTAssertEqual(recovered, received)
        let closed = await cold.invalidateAndAwaitForAccountTransition()
        XCTAssertTrue(closed)
        let clean = try open(retry: false)
        XCTAssertNotNil(clean.nativeReleaseAdmission)
        XCTAssertTrue(try XCTUnwrap(clean.container) !== XCTUnwrap(denied.container))
        // Same-process reopen qualification only; abrupt process death is separate.
    }

    private func fixture(_ root: URL, beforeAttempt: ((Int) throws -> Void)? = nil) throws -> PersistentStoreBootstrapSession {
        try PersistentStoreBootstrapSession.fixture(
            schema: Schema(versionedSchema: CurrentSchema.self),
            storeURL: root.appendingPathComponent("default.store"), anchor: root,
            beforeAttempt: beforeAttempt
        )
    }

    private func temporaryRoot() throws -> URL {
        // Core Data can retain SQLite/WAL descriptors beyond visible container
        // lifetime. Keep these unique disk fixtures until the process exits,
        // matching MigrationPlanTests; never unlink an active SQLite vnode.
        try StoreRecoveryTestSupport.makeTempDirectory().resolvingSymlinksInPath()
    }

    private enum Stub: Error { case ordinary }
}
