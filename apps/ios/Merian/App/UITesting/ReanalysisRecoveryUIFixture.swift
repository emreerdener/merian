#if DEBUG
import CryptoKit
import Foundation
import Observation
import SwiftData

extension UITestSeedCoordinator {
    static var reanalysisRecoveryRestartEnabled: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains("-seedReanalysisRecoveryRestart")
    }
    static var reanalysisRecoverySuccessEnabled: Bool {
        reanalysisRecoveryRestartEnabled && ProcessInfo.processInfo.arguments.contains("-seedReanalysisRecoverySuccess")
    }
}

/// Disposable persisted reanalysis. The normal UI seed never owns this store.
@MainActor @Observable final class ReanalysisRecoveryUIFixture {
    let container: ModelContainer
    let root: URL
    let media: String
    let identity: OfflineQueueWork.Reanalysis
    let reopened: Bool
    let cloud: ObservationHistoryCloudClient
    private(set) var fingerprint = ""
    private(set) var requestDigest = ""
    private(set) var selection = ""
    private(set) var charge = 0
    private(set) var checks = 0
    private(set) var forbidden = 0
    private(set) var failure = ""
    private(set) var photo: ReanalysisStatusViewModel?
    private(set) var audio: CaptureAudioSavedRequestsModel?
    private(set) var video: CaptureVideoSavedRequestsModel?
    private(set) var history: IdentificationHistoryViewModel?
    private(set) var historyBoundary: ReanalysisRecoveryUIHistory?
    private(set) var isCompleted = false
    private(set) var completionNotifications = 0
    private let audioCompletionOwner = ObservationAudioExecutionOwner()
    private var pending: CheckedContinuation<Void, Never>?
    private var closing = false
    var presented = false
    private var scope: UUID?

    init(progress: (String) -> Void) async throws {
        guard UITestSeedCoordinator.reanalysisRecoveryRestartEnabled,
              let raw = ProcessInfo.processInfo.environment["UITestKeychainNamespace"], let namespace = UUID(uuidString: raw),
              let mode = ProcessInfo.processInfo.environment["ReanalysisRecoveryMedia"], ["photo", "audio", "video"].contains(mode) else {
            throw MerianError.invalidResponse
        }
        media = mode
        let suffix = mode == "photo" ? "71" : (mode == "audio" ? "72" : "73")
        identity = .init(observationID: UUID(uuidString: PublicationConsentUIFixture.observation)!,
            sourceAnalysisID: UUID(uuidString: PublicationConsentUIFixture.selected)!,
            analysisID: UUID(uuidString: "00000000-0000-4000-8000-0000000000" + suffix)!, ownerID: PublicationConsentUIFixture.owner)
        root = URL.applicationSupportDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("reanalysis-recovery-ui-" + namespace.uuidString, isDirectory: true)
        guard root.resolvingSymlinksInPath() == root.standardizedFileURL else { throw MerianError.invalidResponse }
        progress("directory")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var rootValue = root, attributes = URLResourceValues(); attributes.isExcludedFromBackup = true
        try rootValue.setResourceValues(attributes)
        let url = root.appendingPathComponent("history.store")
        guard url.resolvingSymlinksInPath() == url.standardizedFileURL else { throw MerianError.invalidResponse }
        reopened = FileManager.default.fileExists(atPath: url.path)
        progress("container")
        let schema = Schema(versionedSchema: CurrentSchema.self)
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let history = try PublicationConsentUIFixture(container: container, namedReview: false, confirmationUndo: false, candidateConfirmation: false)
        cloud = history.cloud
        if !reopened {
            progress("history")
            try history.seed(context: container.mainContext); try container.mainContext.save()
            progress("held request")
            try await ReanalysisRecoveryUISeed.create(media: media, child: identity.analysisID, root: root, container: container, cloud: cloud)
        }
        progress("verify")
        if UITestSeedCoordinator.reanalysisRecoverySuccessEnabled, reopened {
            guard FileManager.default.fileExists(atPath: ReanalysisRecoveryUIHistory.file(in: root).path) else { throw MerianError.invalidResponse }
            historyBoundary = try ReanalysisRecoveryUIHistory(witness: nil, identity: identity, media: media,
                root: root, container: container, baseline: cloud)
            if let historyBoundary, try historyBoundary.hasTerminalReceipt() {
                try historyBoundary.verifyTerminal(); isCompleted = true
                fingerprint = historyBoundary.witness.originalFingerprint
                requestDigest = Self.digest(historyBoundary.witness.request)
                selection = historyBoundary.ledger.selected
                charge = historyBoundary.ledger.chargedWhenAvailable ?? -1
                guard charge == 30_000 else { throw MerianError.invalidResponse }
                return
            }
        }
        let facts = try currentFacts()
        fingerprint = facts.fingerprint; requestDigest = facts.request; selection = facts.selection
        try readBudget()
        if UITestSeedCoordinator.reanalysisRecoverySuccessEnabled {
            if historyBoundary == nil {
                let witness = try await ReanalysisRecoveryUIResult.create(media: media, identity: identity, root: root,
                    container: container, cloud: cloud, fingerprint: fingerprint)
                historyBoundary = try ReanalysisRecoveryUIHistory(witness: witness, identity: identity, media: media,
                    root: root, container: container, baseline: cloud)
            }
            guard let historyBoundary, historyBoundary.witness.originalFingerprint == fingerprint,
                  Self.digest(historyBoundary.witness.request) == requestDigest else { throw MerianError.invalidResponse }
        }
    }

    func open() {
        guard !presented, !closing, !isCompleted else { return }
        do {
            try verify()
            let token = UUID(); scope = token
            let container = container, owner = identity.ownerID, observation = identity.observationID, root = root
            let valid: @MainActor @Sendable () -> Bool = { true }
            if media == "photo" {
                let session = try IdentificationHistorySession(observation: observation.uuidString.lowercased(), container: container,
                    cloud: cloud, currentGeneration: { 1 }, sessionIsCurrent: { $0.userID == owner && !$0.isAnonymous })
                photo = ReanalysisStatusViewModel(dependencies: session.operationStatusDependencies(retirement: .init(ownership: .init(),
                    fetch: { [weak self] _, _, _ in self?.forbidden += 1; throw MerianError.invalidResponse },
                    wake: { [weak self] in self?.forbidden += 1 }, recover: { [weak self] intent, validate in
                        guard let self, intent.identity == identity,
                              Self.digest(intent.request.body) == requestDigest else { throw MerianError.invalidResponse }
                        try validate()
                        if let result = try availableResult() { try validate(); return result }
                        try await holdRead(); try validate(); return nil
                    }, completionAttempted: { [weak self] in
                        guard let self else { return }
                        if historyBoundary?.ledger.available == true { completionNotifications += 1 } else { forbidden += 1 }
                    }, documents: { root })))
            } else if media == "audio" {
                let access = CaptureAudioReanalysisAccess.prepared(account: cloud, ownership: .init(),
                    configuration: .init(authorize: { [weak self] _, _ in self?.forbidden += 1; throw MerianError.invalidResponse },
                        start: { [weak self] _, _, _, _ in self?.forbidden += 1; return .unavailable },
                        recover: { [weak self] key, proof, candidate, _ in
                            guard let self, candidate === container, proof.preparation.identity == identity,
                                  key.snapshot.work.consumedAttempt != nil,
                                  Self.digest(key.snapshot.work.intent.request.body) == requestDigest,
                                  try ObservationAudioExecutionStore.read(proof, container: container, isCurrent: valid) == key.snapshot else {
                                throw MerianError.invalidResponse
                            }
                            if let result = try availableResult() { return try await completeAudio(key, proof: proof, result: result) }
                            try await holdRead(); return false
                        }), currentOwner: { owner }, generation: { 1 }, sessionIsCurrent: { $0.userID == owner && !$0.isAnonymous },
                    containerIsCurrent: { $0 === container }, documents: { root })
                let status = CaptureAudioStatusAccess.prepared(account: cloud, owner: .init(), reader: .init(),
                    currentOwner: { owner }, generation: { 1 }, sessionIsCurrent: { $0.userID == owner && !$0.isAnonymous }, containerIsCurrent: { $0 === container })
                audio = CaptureAudioSavedRequestsModel(status: try status.open(owner, observation, container),
                    openResume: { try access.openResume($0, container) }, isPresented: { [weak self] in self?.scope == token })
            } else {
                let access = CaptureVideoResumeAccess.prepared(account: cloud, ownership: .init(),
                    configuration: .init(start: { [weak self] _, _, _, _, _ in self?.forbidden += 1; return .unavailable },
                        recover: { [weak self] key, proof, candidate, _ in
                            guard let self, candidate === container, proof.preparation.identity == identity, key.snapshot.work.consumed,
                                  Self.digest(key.snapshot.work.request.body) == requestDigest,
                                  try ObservationVideoExecutionStore.read(proof: proof, container: container, isCurrent: valid) == key.snapshot else {
                                throw MerianError.invalidResponse
                            }
                            if let result = try availableResult() {
                                _ = try ObservationVideoExecutionStore.complete(key.snapshot, resultBytes: result, proof: proof,
                                    container: container, isCurrent: valid)
                                try historyBoundary?.verifyTerminal(); completionNotifications += 1
                                return true
                            }
                            try await holdRead(); return false
                        }), currentOwner: { owner }, generation: { 1 }, sessionIsCurrent: { $0.userID == owner && !$0.isAnonymous },
                    containerIsCurrent: { $0 === container }, documents: { root })
                let status = CaptureVideoStatusAccess.prepared(account: cloud, owner: .init(), reader: .init(),
                    currentOwner: { owner }, generation: { 1 }, sessionIsCurrent: { $0.userID == owner && !$0.isAnonymous }, containerIsCurrent: { $0 === container })
                video = CaptureVideoSavedRequestsModel(status: try status.open(owner, observation, container),
                    openResume: { try access.openResume($0, container) }, isPresented: { [weak self] in self?.scope == token })
            }
            presented = true
        } catch { failure = "Recovery fixture open failed" }
    }

    /// Hold only the synthetic response. Close releases it and joins the real
    /// checking model before publishing settled-budget diagnostics or relaunch.
    private func holdRead() async throws {
        try verify(); guard pending == nil, !closing else { throw MerianError.invalidResponse }
        checks += 1
        await withTaskCancellationHandler {
            await withCheckedContinuation { pending = $0 }
        } onCancel: { Task { @MainActor [weak self] in self?.releaseRead() } }
        try verify()
    }
    private func releaseRead() { let wait = pending; pending = nil; wait?.resume() }

    func close() async {
        guard !closing else { return }; closing = true
        let checker = photo?.recovery ?? audio?.recovery ?? video?.recovery
        photo?.close(); audio?.close(); video?.close(); history?.close(); scope = nil
        releaseRead()
        while checker?.isRunning == true { await Task.yield() }
        while historyBoundary?.isDelivering == true { await Task.yield() }
        do {
            if let historyBoundary, try historyBoundary.hasTerminalReceipt() {
                try historyBoundary.verifyTerminal(); isCompleted = true
                selection = historyBoundary.ledger.selected
            } else { try verify(); try readBudget() }
        } catch { failure = "Recovery fixture close failed" }
        photo = nil; audio = nil; video = nil; history = nil; presented = false; closing = false
    }

    func makeResultAvailable() {
        do { guard !presented, !isCompleted, let historyBoundary else { throw MerianError.invalidResponse }; try historyBoundary.makeAvailable() } catch { failure = "Synthetic result availability failed" }
    }
    func openHistory() {
        do {
            guard !presented, isCompleted, let historyBoundary else { throw MerianError.invalidResponse }
            history = try historyBoundary.open(); presented = true
        } catch { failure = "Recovered History could not open" }
    }

    private func availableResult() throws -> Data? {
        guard let historyBoundary, historyBoundary.ledger.available else { return nil }
        try verify(); guard charge == 30_000, !closing else { throw MerianError.invalidResponse }
        checks += 1
        return historyBoundary.witness.result
    }

    private func completeAudio(_ key: ObservationAudioExecutionOwner.Key, proof: ObservationAudioPreparation.Verified,
                               result: Data) async throws -> Bool {
        let service = ObservationAudioExecutionService(dependencies: .init(
            read: { [weak self] _, _, _ in self?.forbidden += 1; throw MerianError.invalidResponse },
            upload: { [weak self] _, _, _ in self?.forbidden += 1; throw MerianError.invalidResponse },
            authorize: { [weak self] _, _ in self?.forbidden += 1; throw MerianError.invalidResponse },
            analyze: { [weak self] _, _, _, _ in self?.forbidden += 1; throw MerianError.invalidResponse },
            outcome: { claim, before, after in
                try before()
                guard claim.snapshot.work.intent == key.snapshot.work.intent,
                      claim.snapshot.work.consumedAttempt == key.snapshot.work.consumedAttempt,
                      claim.snapshot.work.attempt == key.snapshot.work.attempt + 1 else { throw MerianError.invalidResponse }
                _ = try ObservationReanalysisResult.decode(result, matching: claim.snapshot.work.intent.request)
                try after(); return result
            }))
        let container = container, owner = identity.ownerID
        let current: @MainActor @Sendable () -> Bool = { key.session.userID == owner && !key.session.isAnonymous
            && key.generation == 1 && key.container == ObjectIdentifier(container) }
        var completed = false
        let admission = audioCompletionOwner.start(key, account: cloud, isCurrent: current, operation: { [self] scope in
            completed = await service.run(key.snapshot, proof: proof, container: container, scope: scope,
                cleanup: { [weak self] _ in self?.completionNotifications += 1 }) == .completed
        }, didFinish: {})
        guard case .started = admission, let exit = audioCompletionOwner.captureActualExit(key) else { throw MerianError.invalidResponse }
        await exit.wait()
        guard completed, !audioCompletionOwner.isRunning, forbidden == 0,
              try ObservationReanalysisRecoveredResult.contains(identity, container: container, isCurrent: current,
                decode: { try ObservationReanalysisResult.decode($0, matching: key.snapshot.work.intent.request) }) else { throw MerianError.invalidResponse }
        try historyBoundary?.verifyTerminal()
        return true
    }

    private func readBudget() throws {
        let snapshot = try ObservationReanalysisRecoveryPresentationStore.read(identity, container: container, isCurrent: { true })
        guard snapshot.value.activeReservationID == nil else { throw MerianError.invalidResponse }
        charge = snapshot.value.chargedMilliseconds
    }
    private func verify() throws {
        let facts = try currentFacts()
        guard facts.fingerprint == fingerprint, facts.request == requestDigest, facts.selection == selection, forbidden == 0 else {
            failure = "Recovery fixture immutable state changed"; throw MerianError.invalidResponse
        }
    }
    private static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }

    // These named fixture facts are compared together to detect unintended recovery writes.
    // swiftlint:disable:next large_tuple
    private func currentFacts() throws -> (fingerprint: String, request: String, selection: String) {
        let read = ModelContext(container); read.autosaveEnabled = false
        let rows = try read.fetch(FetchDescriptor<OfflineQueuedScan>()), jobs = try read.fetch(FetchDescriptor<OfflineJobRecord>())
        let parents = try read.fetch(FetchDescriptor<LocalScanRecord>())
        guard rows.count == 1, jobs.count == 1, parents.count == 1, let row = rows.first, let job = jobs.first, let parent = parents.first,
              row.work == .reanalysis(identity), row.id == identity.analysisID.uuidString.lowercased(),
              job.id == OfflineQueueManager.scanIngestionJobId(scanId: row.id), let metadata = job.metadataJSON,
              parent.id == identity.observationID.uuidString.lowercased(), parent.analysisOwnerAccountID == identity.ownerID.uuidString.lowercased(),
              let selected = parent.selectedAnalysisID, selected == identity.sourceAnalysisID.uuidString.lowercased(),
              try read.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 2,
              try read.fetchCount(FetchDescriptor<OfflineQueueEvent>()) == 0 else { throw MerianError.invalidResponse }
        let request: Data
        switch media {
        case "photo":
            let saved = try ObservationReanalysisExecutionStore.read(identity, container: container, isCurrent: { true })
            request = saved.intent.request.body
        case "audio": request = try ObservationAudioExecutionIntent.Work.decode(Data(metadata.utf8)).intent.request.body
        default: request = try ObservationVideoExecutionWork.decode(Data(metadata.utf8)).request.body
        }
        let filesRoot = root.appendingPathComponent("ReanalysisQueue/" + row.id, isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: filesRoot, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
        guard (1...7).contains(files.count) else { throw MerianError.invalidResponse }
        let mediaFacts: [[String: Any]] = try files.map { url in
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard url.resolvingSymlinksInPath() == url.standardizedFileURL,
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  let length = attributes[.size] as? NSNumber, (1...12_582_912).contains(length.intValue) else { throw MerianError.invalidResponse }
            let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
            let bytes = try file.read(upToCount: length.intValue + 1) ?? Data()
            guard bytes.count == length.intValue else { throw MerianError.invalidResponse }
            return ["name": url.lastPathComponent, "bytes": bytes.count, "digest": Self.digest(bytes)]
        }
        let facts: [String: Any] = ["child": row.id, "parent": parent.id, "owner": identity.ownerID.uuidString.lowercased(),
            "source": identity.sourceAnalysisID.uuidString.lowercased(), "selected": selected, "metadata": metadata,
            "media": row.capturedMediaJSON as Any? ?? NSNull(), "paths": row.inferenceImagePaths as Any? ?? NSNull(),
            "queueState": row.scanStateRaw, "queueAttempts": row.queueAttemptCount, "jobState": job.statusRaw,
            "jobAttempts": job.attemptCount, "jobUpdated": job.updatedAt.timeIntervalSince1970, "files": mediaFacts]
        return (Self.digest(try JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys])), Self.digest(request), selected)
    }
}
#endif
