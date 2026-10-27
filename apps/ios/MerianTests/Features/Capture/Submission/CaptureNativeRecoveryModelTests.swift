import Foundation
import Testing
@testable import Merian

@Suite("Native Capture local holding presentation", .serialized)
@MainActor
struct CaptureNativeRecoveryModelTests {
    @Test(arguments: [0, 1, 2])
    func discoveryNeverSelectsOrAuthorizesAnOperation(_ count: Int) async {
        let candidates = (0..<count).map { _ in candidate() }
        let ownerID = candidates.first?.profile.ownerID ?? Self.ownerID
        var reads = 0
        let model = CaptureNativeRecoveryModel(ownerID: ownerID, isCurrent: { true }) {
            reads += 1; return candidates
        }
        await model.open()
        #expect(model.state == .unselected(candidates))
        await model.select(candidate()) // unlisted identity cannot be selected
        #expect(reads == 1)
        if let selected = candidates.last {
            await model.select(selected)
            #expect(model.state == .holding(selected) && reads == 2)
        }
        model.close()
        #expect(model.state == .closed)
    }

    @Test(arguments: ["missing", "changed", "foreign", "profile"])
    func exactRefreshRejectsChangedDurableIdentity(_ change: String) async {
        let original = candidate()
        var returned = [original]
        let model = CaptureNativeRecoveryModel(ownerID: Self.ownerID, isCurrent: { true }) { returned }
        await model.open()
        await model.select(original)
        #expect(model.state == .holding(original))
        switch change {
        case "missing": returned = []
        case "foreign": returned = [candidate(ownerID: UUID())]
        case "profile": returned = [candidate(inventoryID: UUID())]
        default: returned = [candidate(packageID: original.packageID)]
        }
        await model.refresh()
        #expect(model.state == .unavailable)
    }

    @Test(arguments: ["account", "close", "cancel"])
    func lateReadCannotRestoreInvalidPresentation(_ change: String) async {
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        var current = true, reads = 0
        let value = candidate()
        let model = CaptureNativeRecoveryModel(ownerID: Self.ownerID, isCurrent: { current }) {
            reads += 1; await entered.open(); await release.wait(); return [value]
        }
        let task = Task { await model.open() }
        await entered.wait()
        await model.open()
        #expect(reads == 1)
        switch change {
        case "account": current = false
        case "close": model.close()
        default: task.cancel()
        }
        await release.open(); await task.value
        #expect(model.state == (change == "close" ? .closed : .unavailable))
    }

    private static let ownerID = UUID(), inventoryID = UUID(), generation = UUID()
    private func candidate(ownerID: UUID = Self.ownerID, inventoryID: UUID = Self.inventoryID,
                           packageID: UUID = UUID()) -> SharedMediaNativeReceivedCandidate {
        .init(profile: .init(ownerID: ownerID, inventoryID: inventoryID, generation: Self.generation,
            storeIdentity: "synthetic", physicalBinding: "synthetic", receiptDigest: "synthetic"),
            packageID: packageID, draftGeneration: UUID(), operationID: UUID(), revision: 1,
            preparedSHA256: String(repeating: "a", count: 64), receivedSHA256: String(repeating: "b", count: 64))
    }
}
