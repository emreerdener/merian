import Foundation
@testable import Merian
import SwiftData
import XCTest

/// Real isolated SQLite work; no app repository or live provider is installed.
@MainActor
final class PersistencePerformanceTests: XCTestCase {
    private func store() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let url = URL.temporaryDirectory.appendingPathComponent("benchmark-\(UUID()).sqlite")
        // Core Data can retain WAL handles until process exit. Do not unlink live stores.
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
    }

    private var options: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 10
        return options
    }

    func testDurableQueueCommit() throws {
        let container = try store()
        let media = MediaJSONParser.jsonString(from: [.description(ObservationContext(freeText: "Synthetic observation"))])
        let measurementOptions = options
        measurementOptions.invocationOptions = [.manuallyStart]
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: measurementOptions) {
            let context = ModelContext(container)
            let scan = OfflineQueuedScan(capturedMediaJSON: media, scanState: .pending)
            let job = OfflineJobRecord(
                id: OfflineQueueManager.scanIngestionJobId(scanId: scan.id),
                kind: .scanIngestion, subjectId: scan.id, status: .pending
            )
            startMeasuring()
            context.insert(scan)
            context.insert(job)
            do {
                try context.save()
            } catch {
                XCTFail("Durable commit failed: \(error)")
            }
            stopMeasuring()
            do {
                let fresh = ModelContext(container)
                XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<OfflineQueuedScan>()), 1)
                // Verification and cleanup are outside the measured interval, so each
                // sample starts with the same empty queue and a fresh identity map.
                context.delete(scan)
                context.delete(job)
                try context.save()
            } catch {
                XCTFail("Commit verification/cleanup failed: \(error)")
            }
        }
    }

    func testLargeLibraryScalarHydration() throws {
        let container = try store()
        let context = ModelContext(container)
        let media = MediaJSONParser.jsonString(from: [
            .image(.documents("synthetic.webp")), .audio(.documents("synthetic.wav"))
        ])
        for index in 0..<1_000 {
            context.insert(LocalScanRecord(
                id: "benchmark-\(index)", speciesId: "benchmark-species",
                scientificName: "Synthetic subject", commonName: "Synthetic",
                capturedMediaJSON: media
            ))
        }
        try context.save()
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            do {
                // A fresh context prevents the identity map turning later samples into no-ops.
                let reader = ModelContext(container)
                let records = try reader.fetch(FetchDescriptor<LocalScanRecord>())
                XCTAssertEqual(records.count, 1_000)
                XCTAssertEqual(records.reduce(0) { $0 + $1.capturedMediaSnapshot.items.count }, 2_000)
            } catch {
                XCTFail("Library hydration failed: \(error)")
            }
        }
    }

    func testLargeOfflineQueueProjection() throws {
        let container = try store()
        let context = ModelContext(container)
        for _ in 0..<1_000 {
            context.insert(OfflineQueuedScan(scanState: .staged))
        }
        try context.save()
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            do {
                let reader = ModelContext(container)
                let scans = try reader.fetch(FetchDescriptor<OfflineQueuedScan>())
                XCTAssertEqual(scans.map { $0.queuedScanContext() }.count, 1_000)
            } catch {
                XCTFail("Queue projection failed: \(error)")
            }
        }
    }
}
