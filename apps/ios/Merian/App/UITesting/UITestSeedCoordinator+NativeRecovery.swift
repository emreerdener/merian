#if DEBUG
import Foundation
import Observation
import SwiftData
import UIKit

extension UITestSeedCoordinator {
    static var nativeRecoveryEnabled: Bool {
        nativeRecoveryRestartEnabled || nativeRecoveryHistoryEnabled
    }
    static var nativeRecoveryRestartEnabled: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains("-seedNativePhotoRecoveryRestart")
    }
    static var nativeRecoveryHistoryEnabled: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains("-seedNativePhotoRecoveryHistory")
    }
}

/// Disposable native ownership graph, built through existing acquisition and
/// receiving owners. It never mounts the ordinary app's persistent container.
@MainActor @Observable
final class NativeRecoveryUIFixture {
    let container: ModelContainer
    let root: URL
    let reopened: Bool
    let ownerID = UUID(uuidString: "00000000-0000-4000-8000-000000000090")!
    let inventoryID = UUID(uuidString: "00000000-0000-4000-8000-000000000091")!
    let packageID = UUID(uuidString: "00000000-0000-4000-8000-000000000092")!
    let draft = UUID(uuidString: "00000000-0000-4000-8000-000000000093")!
    private let runtime = AuthRuntimeState()
    private var owner: SharedMediaNativeOriginalOwner?
    private(set) var model: CaptureNativeRecoveryModel?
    private(set) var fingerprint = ""
    private(set) var checks = 0
    private(set) var chargedMilliseconds = 0
    private(set) var failure = ""
    private(set) var history: NativeRecoveryUIHistoryFixture?
    private(set) var selection = "none"
    private(set) var opened = false
    var presented = false

    init(progress: (String) -> Void) async throws {
        progress("directories")
        guard UITestSeedCoordinator.nativeRecoveryEnabled,
              let raw = ProcessInfo.processInfo.environment["UITestKeychainNamespace"],
              let namespace = UUID(uuidString: raw) else { throw SharedMediaStorageFailure.closed }
        root = URL.applicationSupportDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("native-recovery-ui-" + namespace.uuidString, isDirectory: true)
        let parent = root.appendingPathComponent("control", isDirectory: true)
        let database = root.appendingPathComponent("database", isDirectory: true)
        for directory in [root, parent, database] {
            guard directory.resolvingSymlinksInPath().path == directory.standardizedFileURL.path else { throw SharedMediaStorageFailure.closed }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var value = directory, attributes = URLResourceValues(); attributes.isExcludedFromBackup = true
            try value.setResourceValues(attributes)
        }
        let url = database.appendingPathComponent("ledger.store")
        guard url.resolvingSymlinksInPath() == url.standardizedFileURL else { throw SharedMediaStorageFailure.closed }
        reopened = FileManager.default.fileExists(atPath: url.path)
        progress("container")
        container = try Self.makeContainer(url)
        if UITestSeedCoordinator.nativeRecoveryHistoryEnabled { history = try NativeRecoveryUIHistoryFixture() }
        let account = PhotoOriginalPreparationOwner.syntheticAccount(ownerID: ownerID, runtime: runtime)
        if !reopened {
            progress("bootstrap")
            let bootstrap = try SharedMediaNativeOriginalOwner.appInitialization(account: account, drain: .init())
            do { _ = try await bootstrap.initializeApp(container: container, parent: parent, inventoryID: inventoryID) } catch { _ = await bootstrap.invalidateAndAwaitForAccountTransition(); throw error }
            guard await bootstrap.invalidateAndAwaitForAccountTransition() else { throw SharedMediaStorageFailure.closed }
        }
        let active = try SharedMediaNativeOriginalOwner.appDispatch(account: account, drain: .init())
        owner = active
        do {
            progress("open")
            _ = try await active.openApp(container: container, parent: parent, inventoryID: inventoryID)
            progress("seed")
            if !reopened { try await seed(active) }
            progress("verify")
            fingerprint = try immutableFingerprint()
            try readBudget()
            guard try await active.discoverAppReceivedCandidates().count == 1 else { throw SharedMediaStorageFailure.closed }
        } catch {
            _ = await active.invalidateAndAwaitForAccountTransition()
            throw error
        }
    }

    private static func makeContainer(_ url: URL) throws -> ModelContainer {
        // Construction owns this fence only until the helper returns. Keeping
        // it in the async initializer would overlap the bootstrap owner's lock.
        let fence = try SharedMediaStoreReadFence(store: url, access: .sharedWriter)
        let schema = Schema(versionedSchema: CurrentSchema.self)
        return try withExtendedLifetime(fence) {
            try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        }
    }

    private func seed(_ active: SharedMediaNativeOriginalOwner) async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        guard let bytes = image.pngData() else { throw SharedMediaStorageFailure.closed }
        let request = try await active.prepareAppOriginal(packageID: packageID, draftGeneration: draft, ordinal: 0, kind: .picker)
        let acquired = try await active.acquireAppOriginal(request) { bytes }
        let original = PhotoOriginalReference(ownerID: ownerID, packageID: packageID, referenceID: request.referenceID,
            assetID: request.assetID, assetGeneration: request.assetGeneration, draftGeneration: draft, referenceRevision: acquired.referenceRevision)
        let metadata = try await active.prepareAppMetadata(packageID: packageID, draftGeneration: draft,
            contexts: [.init(freeText: "  Exact original note\nwith spacing.  ")])
        _ = try await active.saveAppMetadata(metadata)
        try active.setPreparationFault(nil, focusFactory: .qualification(.qualification(worker: { .noCandidates }, drainRegistered: {})))
        let pair = try await active.prepareAndDeliverAppPhoto(original: original,
            recipe: .init(format: .stillImage, isPro: false, cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0))
        let prepared = try await active.stageAppReceiving(packageID: packageID, draftGeneration: draft,
            pairIDs: [try pair.intent().pairID], photoAdmission: .init(authorization: .init(recipient: .gemini, validate: {})))
        _ = try await active.receiveAppPrepared(prepared)
        try await history?.allocate(prepared, owner: active)
    }

    func open() async {
        do {
            await model?.closeAndWait()
            guard let owner else { throw SharedMediaStorageFailure.closed }
            try verify()
            let access = CaptureNativeRecoveryStatusAccess.app(isCurrent: { true }, owner: { owner }) { [self] scan, account, validate in
                try validate(); try verify(); checks += 1
                // Hold this synthetic reply long enough for the explicit Pause
                // action; cancellation joins it before the budget is recorded.
                if checks == 1 && !reopened && history == nil { try await Task.sleep(for: .seconds(20)) }
                try validate(); try verify()
                return try JSONSerialization.data(withJSONObject: ["version": 1, "phase": "observe", "owner_id": account.uuidString.lowercased(),
                    "scan_id": scan.uuidString.lowercased(), "row_exists": true, "job_status": "processing", "original_result": "unavailable"], options: [.sortedKeys])
            }
            if let history {
                model = CaptureNativeRecoveryModel(ownerID: ownerID, isCurrent: { true }, statusAccess: access,
                    initialRead: { try await owner.discoverAppInitialContinuation($0) },
                    initialCompletion: { [self] candidate, validate in
                        let association = try await history.complete(candidate, owner: owner, container: container, validate: validate)
                        selection = try history.selection(container)
                        return association
                    }, initialOpen: { [self] association in
                        try history.open(association, container: container)
                        guard selection == (try history.selection(container)) else { throw SharedMediaStorageFailure.conflict }
                        opened = true
                    }, discover: { try await owner.discoverAppReceivedCandidates() })
            } else {
                model = CaptureNativeRecoveryModel(ownerID: ownerID, isCurrent: { true }, statusAccess: access) {
                    try await owner.discoverAppReceivedCandidates()
                }
            }
            presented = true
        } catch { failure = "Native fixture invariant failed" }
    }

    func close() async {
        await model?.closeAndWait()
        do { try verify(); if history == nil { try readBudget() } } catch { failure = "Native fixture invariant failed" }
        presented = false
    }

    private func received() throws -> (prepared: Data, result: Data) {
        let read = ModelContext(container); read.autosaveEnabled = false
        let rows = try read.fetch(FetchDescriptor<SharedMediaReceivingIntentRecord>())
        guard rows.count == 1, let row = rows.first, row.id == packageID,
              try read.fetchCount(FetchDescriptor<LocalScanRecord>()) <= (history == nil ? 0 : 1) else { throw SharedMediaStorageFailure.conflict }
        guard let prepared = row.preparedData, let result = row.resultData,
              history != nil || (row.allocationData == nil && row.initialAdmissionData == nil && row.initialCompletionData == nil) else { throw SharedMediaStorageFailure.conflict }
        return (prepared, result)
    }
    private func immutableFingerprint() throws -> String {
        let row = try received()
        if history != nil { return SharedMediaAcquisitionEncoding.digest(row.prepared) }
        return SharedMediaAcquisitionEncoding.digest(Data((SharedMediaAcquisitionEncoding.digest(row.prepared)
            + SharedMediaAcquisitionEncoding.digest(row.result)).utf8))
    }
    private func verify() throws {
        guard try immutableFingerprint() == fingerprint else { throw SharedMediaStorageFailure.conflict }
    }
    private func readBudget() throws {
        let prepared = try SharedMediaNativeReceivingIntent.Prepared.decode(received().prepared)
        let read = ModelContext(container), id = prepared.queueID.uuidString.lowercased()
        let rows = try read.fetch(FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == id }))
        guard rows.count == 1 else { throw SharedMediaStorageFailure.conflict }
        guard let data = rows.first?.recoveryPresentationData else { chargedMilliseconds = 0; return }
        let value = try AnalysisRecoveryPresentation.decode(data,
            identity: .init(ownerID: ownerID, observationID: prepared.observationID, operationID: prepared.operationID))
        guard value.activeReservationID == nil else { throw SharedMediaStorageFailure.busy }
        chargedMilliseconds = value.chargedMilliseconds
    }
}
#endif
