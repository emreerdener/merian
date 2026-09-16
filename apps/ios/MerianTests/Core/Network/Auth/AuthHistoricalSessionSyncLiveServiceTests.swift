@testable import Merian
import XCTest

private actor AuthHistoricalSessionSyncTestGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilSuspended() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func release() {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }
}

@MainActor
final class HistoricalSessionSyncLiveServiceTests: XCTestCase {
    func testSyncPreservesStampPreferencesFenceAndScanOrder() async {
        let gate = AuthHistoricalSessionSyncTestGate()
        var events: [String] = []
        let isCurrent = true
        let service = AuthHistoricalSessionSyncLiveService(
            dependencies: HistoricalSessionSyncLiveDependencies(
                makeWork: {
                    events.append("make-work")
                    return AuthHistoricalSessionSyncWork(
                        markStarted: {
                            events.append("mark-started")
                        },
                        syncPreferredNames: {
                            events.append("sync-preferred-names")
                            await gate.wait()
                        },
                        syncHistoricalScans: {
                            events.append("sync-historical-scans")
                        }
                    )
                }
            )
        )

        service.schedule(isCurrentSession: { isCurrent })
        await gate.waitUntilSuspended()
        XCTAssertEqual(
            events,
            ["make-work", "mark-started", "sync-preferred-names"]
        )

        await gate.release()
        await waitUntil { events.last == "sync-historical-scans" }

        XCTAssertTrue(isCurrent)
        XCTAssertEqual(
            events,
            [
                "make-work",
                "mark-started",
                "sync-preferred-names",
                "sync-historical-scans"
            ]
        )
    }

    func testSessionDriftAfterPreferenceSyncStopsHistoricalScan() async {
        let gate = AuthHistoricalSessionSyncTestGate()
        var events: [String] = []
        var isCurrent = true
        var didFinishPreferredNames = false
        let service = AuthHistoricalSessionSyncLiveService(
            dependencies: HistoricalSessionSyncLiveDependencies(
                makeWork: {
                    AuthHistoricalSessionSyncWork(
                        markStarted: {
                            events.append("mark-started")
                        },
                        syncPreferredNames: {
                            events.append("sync-preferred-names")
                            await gate.wait()
                            didFinishPreferredNames = true
                        },
                        syncHistoricalScans: {
                            events.append("sync-historical-scans")
                        }
                    )
                }
            )
        )

        service.schedule(isCurrentSession: { isCurrent })
        await gate.waitUntilSuspended()
        isCurrent = false
        await gate.release()
        await waitUntil { didFinishPreferredNames }

        XCTAssertEqual(
            events,
            ["mark-started", "sync-preferred-names"]
        )
    }

    func testServiceDeinitCancelsSuspendedSyncWithoutSelfRetention() async {
        let gate = AuthHistoricalSessionSyncTestGate()
        var didStart = false
        var didFinishPreferredNames = false
        var didScan = false
        var service: AuthHistoricalSessionSyncLiveService? =
            AuthHistoricalSessionSyncLiveService(
                dependencies: HistoricalSessionSyncLiveDependencies(
                    makeWork: {
                        AuthHistoricalSessionSyncWork(
                            markStarted: {
                                didStart = true
                            },
                            syncPreferredNames: {
                                await gate.wait()
                                didFinishPreferredNames = true
                            },
                            syncHistoricalScans: {
                                didScan = true
                            }
                        )
                    }
                )
            )
        service?.schedule(isCurrentSession: { true })
        await gate.waitUntilSuspended()
        weak let releasedService = service

        service = nil

        XCTAssertTrue(didStart)
        XCTAssertNil(releasedService)
        await gate.release()
        await waitUntil { didFinishPreferredNames }
        XCTAssertFalse(didScan)
    }

    private func waitUntil(
        _ predicate: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<2_000 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for historical sync.", file: file, line: line)
    }
}
