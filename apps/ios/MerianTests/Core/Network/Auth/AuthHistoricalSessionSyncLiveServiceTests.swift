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
    func testForegroundAndListenerCoalesceUntilSharedWorkCompletes() async {
        let gate = AuthHistoricalSessionSyncTestGate()
        let key = makeKey()
        var makeCount = 0, stampCount = 0, scanCount = 0
        let service = AuthHistoricalSessionSyncLiveService(dependencies: .init(makeWork: {
            makeCount += 1
            return AuthHistoricalSessionSyncWork(
                markStarted: { stampCount += 1 },
                syncPreferredNames: { await gate.wait() },
                syncHistoricalScans: { scanCount += 1 }
            )
        }))
        let foreground = service.schedule(key: key, isCurrentSession: { true })
        await gate.waitUntilSuspended()
        let listener = service.schedule(key: key, isCurrentSession: { true })
        XCTAssertEqual(makeCount, 1)
        XCTAssertEqual(stampCount, 1)
        XCTAssertEqual(scanCount, 0)
        await gate.release()
        await foreground?.value
        await listener?.value
        XCTAssertEqual(scanCount, 1)
    }

    func testReplacementFencesOldGenerationAndCannotBeClearedByItsCompletion() async {
        for changesAccount in [false, true] {
            let oldGate = AuthHistoricalSessionSyncTestGate()
            let newGate = AuthHistoricalSessionSyncTestGate()
            let oldKey = makeKey()
            let newKey = AuthHistoricalSessionSyncKey(
                session: changesAccount ? makeKey().session : oldKey.session,
                authGeneration: oldKey.authGeneration + 1
            )
            var makeCount = 0
            var scannedWork: [Int] = []
            var oldIsCurrent = true
            let service = AuthHistoricalSessionSyncLiveService(dependencies: .init(makeWork: {
                makeCount += 1
                let workNumber = makeCount
                return AuthHistoricalSessionSyncWork(
                    markStarted: {},
                    syncPreferredNames: {
                        if workNumber == 1 { await oldGate.wait() }
                        if workNumber == 2 { await newGate.wait() }
                    },
                    syncHistoricalScans: { scannedWork.append(workNumber) }
                )
            }))
            let old = service.schedule(key: oldKey, isCurrentSession: { oldIsCurrent })
            await oldGate.waitUntilSuspended()
            oldIsCurrent = false
            let replacement = service.schedule(key: newKey, isCurrentSession: { true })
            await newGate.waitUntilSuspended()
            XCTAssertNil(service.schedule(key: oldKey, isCurrentSession: { false }))
            await oldGate.release()
            await old?.value
            let joinedReplacement = service.schedule(key: newKey, isCurrentSession: { true })
            XCTAssertEqual(makeCount, 2)
            XCTAssertTrue(scannedWork.isEmpty)
            await newGate.release()
            await replacement?.value
            await joinedReplacement?.value
            XCTAssertEqual(scannedWork, [2])

            // Completed work is not a permanent throttle: a later admitted
            // foreground request must be able to synchronize again.
            await service.schedule(key: newKey, isCurrentSession: { true })?.value
            XCTAssertEqual(scannedWork, [2, 3])
        }
    }

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

        service.schedule(key: makeKey(), isCurrentSession: { isCurrent })
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

        service.schedule(key: makeKey(), isCurrentSession: { isCurrent })
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
        service?.schedule(key: makeKey(), isCurrentSession: { true })
        await gate.waitUntilSuspended()
        weak let releasedService = service

        service = nil

        XCTAssertTrue(didStart)
        XCTAssertNil(releasedService)
        await gate.release()
        await waitUntil { didFinishPreferredNames }
        XCTAssertFalse(didScan)
    }

    private func makeKey() -> AuthHistoricalSessionSyncKey {
        AuthHistoricalSessionSyncKey(
            session: AuthTransitionSession(userID: UUID(), isAnonymous: false),
            authGeneration: 1
        )
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
