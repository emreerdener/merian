import Darwin
import Foundation
import SwiftData
import XCTest
@testable import Merian

/// Opt-in single-attempt process closure control, never selected by broad
/// acceptance manifests. Ordinary runs verify only the inert arming guard.
@MainActor
final class SharedMediaStageExitProbeTests: XCTestCase {
    private typealias Probe = SharedMediaStageExitProbeSupport
    private typealias Records = SharedMediaStageExitProbeRecords
    private typealias Locations = SharedMediaStageExitProbeLocation

    private func location(_ invocation: Probe.Invocation) throws -> Locations.Location {
        let anchor = try Probe.read(Locations.Anchor.self, name: "anchor.json", root: invocation.root)
        try Records.require(anchor.ticket == invocation.ticket)
        let current = try Locations.current(ticket: invocation.ticket, probeRoot: invocation.root)
        try current.requireSamePhysicalRoot(as: anchor.location)
        return current
    }

    func testNoSaveChildExit() async throws {
        guard let invocation = try Probe.invocation(selector: Probe.childSelector, phase: "no-save-child", testBundle: Bundle(for: Self.self)) else { return }
        let ticket = try Probe.read(Probe.Ticket.self, name: "ticket.json", root: invocation.root)
        try Records.require(ticket == invocation.ticket)
        let initialLocation = try location(invocation) // Before any fixture creation.
        let process = Records.Process(ticket: ticket, pid: getpid(), processNonce: UUID(), location: initialLocation)
        // This precedes every fixture creation/save; a failed setup cannot retry.
        try Probe.create(process, name: "child-attempt.json", root: invocation.root)
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests()
            .fixture(temporaryStore: true, fenceBootstrap: true)
        let pairIDs = try SharedMediaNativeReceivingStagingTests().pairIDs(request)
        let prepared = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: pairIDs)
        _ = try await owner.receiveAppPrepared(prepared)
        try owner.setMetadataFault { _ in throw Probe.Failure.invalid }
        _ = try await owner.inspectApp()
        let store = try XCTUnwrap(h.container.configurations.first).url
        try Records.requireHeld(store)
        let binding = try Records.binding(store), releaseID = UUID()
        let data = URL(fileURLWithPath: initialLocation.dataPath)
        let fixture = try Records.Fixture(location: initialLocation,
            storeRelative: Records.relative(store, below: data), controlRelative: Records.relative(h.parent, below: data),
            physical: Records.physical(store: store, control: h.parent, data: data),
            storeIdentity: SharedMediaNativeEligibility.storeIdentity(at: store),
            fenceParent: binding.parent, fenceControl: binding.control,
            inventoryID: h.inventoryID, packageID: h.packageID, ownerID: h.ownerID, releaseID: releaseID,
            state: SharedMediaStageExitProbeState.capture(container: h.container, inventoryID: h.inventoryID,
                packageID: h.packageID, releaseID: releaseID))
        _ = try Records.paths(fixture, current: location(invocation))
        try Probe.create(fixture, name: "fixture.json", root: invocation.root)
        try Probe.create(process, name: "ready.json", root: invocation.root)
        try Probe.create(ticket, name: "ready-published.json", root: invocation.root)

        // The host must register its process-identity-bound exit watch first.
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        var observer: Records.Observer?
        while ContinuousClock.now < deadline {
            if try Records.observerPublished(root: invocation.root) {
                observer = try Probe.read(Records.Observer.self, name: "observer.json", root: invocation.root)
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        let acknowledgement = try XCTUnwrap(observer)
        try Records.require(acknowledgement.process == process && acknowledgement.startSeconds > 0)
        try Records.require(acknowledgement.executable == Bundle.main.executableURL?.resolvingSymlinksInPath().path)
        try Records.requireHeld(store)
        try Records.require(try Records.binding(store) == binding)
        _ = try Records.paths(fixture, current: location(invocation))
        try Records.require(try SharedMediaStageExitProbeState.capture(container: h.container,
            inventoryID: h.inventoryID, packageID: h.packageID, releaseID: releaseID) == fixture.state)
        let boundary = try Records.Boundary(observer: acknowledgement, phase: "no-save-child", intendedExit: 86,
            fixtureSHA256: SharedMediaAcquisitionEncoding.digest(SharedMediaNativeDraftEnvelope.bytes(fixture)))
        // No suspension, owner invalidation or graceful return after this point.
        try withExtendedLifetime((h, owner)) {
            try Probe.create(boundary, name: "boundary.json", root: invocation.root)
            let sentinel = "MERIAN_STAGE_EXIT_BOUNDARY " + ticket.nonce.uuidString.lowercased() + "\n"
            sentinel.withCString { _ = fputs($0, stderr) }
            fflush(stderr)
            _exit(86)
        }
    }

    func testNoSaveReadback() async throws {
        guard let invocation = try Probe.invocation(selector: Probe.readerSelector, phase: "no-save-reader", testBundle: Bundle(for: Self.self)) else { return }
        let ticket = try Probe.read(Probe.Ticket.self, name: "ticket.json", root: invocation.root)
        let currentLocation = try location(invocation) // Before fixture path resolution.
        let attempt = try Probe.read(Records.Process.self, name: "child-attempt.json", root: invocation.root)
        let observer = try Probe.read(Records.Observer.self, name: "observer.json", root: invocation.root)
        let boundary = try Probe.read(Records.Boundary.self, name: "boundary.json", root: invocation.root)
        let closure = try Probe.read(Records.Closure.self, name: "closure.json", root: invocation.root)
        let fixture = try Probe.read(Records.Fixture.self, name: "fixture.json", root: invocation.root)
        try Records.require(ticket == invocation.ticket && attempt.ticket == ticket && observer.process == attempt
            && fixture.location == attempt.location)
        try Records.require(boundary.observer == observer && boundary.phase == "no-save-child" && boundary.intendedExit == 86)
        try Records.require(closure.boundary == boundary && closure.processTerminationObserved && closure.pidAbsent
            && closure.invocationEnded && closure.outerExit != 0 && !closure.numericHostStatusObserved)
        try Records.require(boundary.fixtureSHA256 == SharedMediaAcquisitionEncoding.digest(SharedMediaNativeDraftEnvelope.bytes(fixture)))
        try Records.require(attempt.pid != getpid() && kill(attempt.pid, 0) == -1 && errno == ESRCH)
        try Probe.create(ticket, name: "reader-attempt.json", root: invocation.root)
        let paths = try Records.paths(fixture, current: currentLocation)
        try Probe.create(Records.presence(paths.store), name: "before-open.json", root: invocation.root)
        var bootstrap: SharedMediaStoreReadFence? = try .init(store: paths.store, access: .sharedWriter, requireExisting: true)
        let binding = try XCTUnwrap(bootstrap).binding()
        try Records.require(binding.parent == fixture.fenceParent && binding.control == fixture.fenceControl)
        try Records.require(try SharedMediaNativeEligibility.storeIdentity(at: paths.store) == fixture.storeIdentity)
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
            url: paths.store, cloudKitDatabase: .none)])
        _ = try Records.paths(fixture, current: location(invocation))
        try Records.require(try XCTUnwrap(bootstrap).binding() == binding)
        bootstrap = nil // Constructor-only guard hands off to the complete owner.
        let runtime = AuthRuntimeState()
        let account = PhotoOriginalPreparationOwner.syntheticAccount(ownerID: fixture.ownerID, runtime: runtime)
        let owner = try SharedMediaNativeOriginalOwner.appDispatch(account: account, drain: .init())
        _ = try await owner.openApp(container: container, parent: paths.control, inventoryID: fixture.inventoryID)
        try owner.setMetadataFault { _ in throw Probe.Failure.invalid }
        try Records.requireHeld(paths.store)
        try Records.require(try Records.binding(paths.store) == binding)
        try Records.require(try SharedMediaNativeEligibility.storeIdentity(at: paths.store) == fixture.storeIdentity)
        _ = try await owner.inspectApp()
        let current = try SharedMediaStageExitProbeState.capture(container: container, inventoryID: fixture.inventoryID,
            packageID: fixture.packageID, releaseID: fixture.releaseID)
        try Records.require(current == fixture.state && !container.mainContext.hasChanges)
        let finalLocation = try location(invocation)
        _ = try Records.paths(fixture, current: finalLocation)
        try withExtendedLifetime((runtime, owner)) {
            try Probe.create(Records.Readback(closure: closure, location: finalLocation), name: "readback.json", root: invocation.root)
        }
        try Records.require(await owner.invalidateAndAwaitForAccountTransition())
    }
}
