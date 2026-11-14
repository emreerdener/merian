#if DEBUG
import Foundation
import Observation
import SwiftData
import SwiftUI

extension UITestSeedCoordinator {
    static var queuedObservationEnabled: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains("-seedQueuedObservationRestart")
    }
}

/// Ordinary held queue presentation on a disposable disk store. Auth and the
/// server observation are synthetic; no production library or network is used.
@MainActor @Observable
final class QueuedObservationUIFixture {
    let container: ModelContainer
    let owner: UUID
    let ids = ["00000000-0000-4000-8000-000000000081", "00000000-0000-4000-8000-000000000082"]
    let reopened: Bool
    private(set) var fingerprint = ""
    private(set) var checks = 0
    private(set) var retries = 0
    private(set) var events = 0
    private(set) var error = ""
    private(set) var context: QueuedScanContext?
    private(set) var model: InsightSheetViewModel?
    var presented = false
    private var perScanChecks: [String: Int] = [:]

    init() throws {
        guard UITestSeedCoordinator.queuedObservationEnabled,
              let raw = ProcessInfo.processInfo.environment["UITestKeychainNamespace"],
              let namespace = UUID(uuidString: raw),
              let owner = UUID(uuidString: "00000000-0000-4000-8000-000000000080") else { throw MerianError.invalidResponse }
        self.owner = owner
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("queued-observation-ui-" + namespace.uuidString, isDirectory: true)
        guard root.resolvingSymlinksInPath().path == root.standardizedFileURL.path else { throw MerianError.invalidResponse }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = root.appendingPathComponent("queue.sqlite")
        guard url.resolvingSymlinksInPath() == url.standardizedFileURL else { throw MerianError.invalidResponse }
        reopened = FileManager.default.fileExists(atPath: url.path)
        let schema = Schema(versionedSchema: CurrentSchema.self)
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        if !reopened {
            let seed = ModelContext(container); seed.autosaveEnabled = false
            for (index, id) in ids.enumerated() {
                let media = CapturedMediaSnapshot(items: index == 0
                    ? [.audio(.documents("synthetic-held-audio.wav"))]
                    : [.video(.init(video: .documents("synthetic-held-video.mp4")))])
                seed.insert(OfflineQueuedScan(id: id, capturedMediaJSON: media.jsonString,
                    scanState: .failed, fieldNotes: "Exact original optional note", queueLastErrorCode: "server_result", queueNeedsAttention: true))
                let funding = ScanFundingReservation(accountId: owner, scanId: id, source: .deferredFlash)
                seed.insert(OfflineJobRecord(id: "scan-ingestion:" + id, kind: .scanIngestion, subjectId: id,
                    status: .needsAttention, metadataJSON: OfflineScanJobMetadataContract.settingFunding(funding, in: nil)))
            }
            try seed.save()
        }
        fingerprint = try currentFingerprint()
        OfflineQueueManager.shared.isOnline = true
    }

    func open(_ index: Int) {
        do {
            try verify()
            let id = ids[index], read = ModelContext(container)
            var query = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == id }); query.fetchLimit = 1
            guard let queue = try read.fetch(query).first else { throw MerianError.invalidResponse }
            let context = queue.queuedScanContext()
            self.context = context; model = InsightSheetViewModel(queuedContext: context); presented = true
        } catch { self.error = "Fixture invariant failed" }
    }

    var dependencies: QueuedContentDependencies {
        .init(readObservation: { [weak self] _, id, current in
            guard let self else { throw MerianError.invalidResponse }
            try verify()
            let result = try await QueuedContentDependencies.readObservation(scanID: id, ownerID: owner,
                container: container, isCurrent: current, send: { [self] scan, owner, validate in
                    try validate(); self.checks += 1
                    let stage = self.perScanChecks[id, default: 0] % 3; self.perScanChecks[id, default: 0] += 1
                    return try JSONSerialization.data(withJSONObject: ["version": 1, "phase": "observe",
                        "owner_id": owner.uuidString.lowercased(), "scan_id": scan.uuidString.lowercased(),
                        "row_exists": stage != 0, "job_status": stage == 0 ? NSNull() : (stage == 1 ? "processing" : "complete") as Any,
                        "original_result": "unavailable"], options: [.sortedKeys])
                })
            try verify(); return result
        }, retryQueuedScanNow: { [weak self] _, _ in self?.retries += 1; return false },
            loadQueuedContext: QueuedContentDependencies.live.loadQueuedContext,
            publishScanLibraryChanged: { [weak self] in self?.events += 1 })
    }

    private func verify() throws {
        guard try currentFingerprint() == fingerprint, retries == 0, events == 0 else {
            error = "Fixture invariant failed"; throw MerianError.invalidResponse
        }
    }

    private func currentFingerprint() throws -> String {
        let read = ModelContext(container); read.autosaveEnabled = false
        guard try read.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 2,
              try read.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 2,
              try read.fetchCount(FetchDescriptor<LocalScanRecord>()) == 0,
              try read.fetchCount(FetchDescriptor<OfflineQueueEvent>()) == 0 else { throw MerianError.invalidResponse }
        let values: [[String: Any]] = try ids.map { id in
            let s = try OfflineQueueDurableAuthorityReader.observation(scanId: id, ownerID: owner, from: container)
            return ["scan": s.scanID.uuidString, "queue": s.queueID, "timestamp": s.queueTimestamp.timeIntervalSince1970,
                "state": s.state.rawValue, "attention": s.needsAttention, "media": s.capturedMedia as Any? ?? NSNull(),
                "note": s.fieldNotes as Any? ?? NSNull(), "queueUpdated": s.queueUpdatedAt.timeIntervalSince1970,
                "jobUpdated": s.jobUpdatedAt.timeIntervalSince1970, "visual": s.visualMedia as Any? ?? NSNull(),
                "inference": s.inferencePaths as Any? ?? NSNull(), "staged": s.stagedKeys as Any? ?? NSNull(),
                "queueAttempts": s.queueAttempts, "job": s.jobID, "jobCreated": s.jobCreatedAt.timeIntervalSince1970,
                "jobStatus": s.jobStatus.rawValue, "jobAttempts": s.jobAttempts, "metadata": s.metadata]
        }
        return SharedMediaAcquisitionEncoding.digest(try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]))
    }
}

struct QueuedObservationUITestPresentation: ViewModifier {
    @State private var fixture: QueuedObservationUIFixture?
    @State private var failure = ""
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let fixture, !fixture.presented {
                VStack {
                    diagnostics(fixture)
                    Button("Open held audio") { fixture.open(0) }.accessibilityIdentifier("QueuedFixtureAudio")
                    Button("Open held video") { fixture.open(1) }.accessibilityIdentifier("QueuedFixtureVideo")
                }.padding().background(.regularMaterial)
            } else if !failure.isEmpty { Text(failure).accessibilityIdentifier("QueuedFixtureError") }
        }
        .task {
            guard UITestSeedCoordinator.queuedObservationEnabled, fixture == nil else { return }
            do { fixture = try QueuedObservationUIFixture() } catch { failure = "Fixture could not open" }
        }
        .fullScreenCover(isPresented: Binding(get: { fixture?.presented == true }, set: { fixture?.presented = $0 })) {
            if let fixture, let context = fixture.context, let model = fixture.model {
                VStack {
                    diagnostics(fixture)
                    Button("Close held submission") { fixture.presented = false }.accessibilityIdentifier("QueuedFixtureClose")
                    QueuedContentView(viewModel: model, queuedContext: context, dependencies: fixture.dependencies)
                }.modelContainer(fixture.container)
            }
        }
    }

    private func diagnostics(_ fixture: QueuedObservationUIFixture) -> some View {
        VStack {
            Text(fixture.reopened ? "reopened" : "created").accessibilityIdentifier("QueuedFixtureStore")
            Text(String(ProcessInfo.processInfo.processIdentifier)).accessibilityIdentifier("QueuedFixtureProcess")
            Text(fixture.fingerprint).accessibilityIdentifier("QueuedFixtureIdentity")
            Text("\(fixture.checks):\(fixture.retries):\(fixture.events)").accessibilityIdentifier("QueuedFixtureCounts")
            if !fixture.error.isEmpty { Text(fixture.error).accessibilityIdentifier("QueuedFixtureError") }
        }.font(.caption2)
    }
}
#endif
