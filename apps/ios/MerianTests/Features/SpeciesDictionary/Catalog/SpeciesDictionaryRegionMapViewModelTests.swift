import UIKit
import XCTest

@testable import Merian

@MainActor
final class SpeciesDictionaryRegionMapViewModelTests: XCTestCase {
    func testRejectsStaleSnapshotCompletion() async {
        let stale = UIImage()
        let current = UIImage()
        let staleLoadStarted = expectation(description: "Old map started")
        var pendingStaleLoad: CheckedContinuation<UIImage?, Never>?
        let viewModel = SpeciesDictionaryRegionMapViewModel(
            dependencies: .init(
                loadSnapshot: { query, _, _, _ in
                    if query == "old" {
                        return await withCheckedContinuation {
                            pendingStaleLoad = $0
                            staleLoadStarted.fulfill()
                        }
                    }
                    return current
                }
            )
        )

        let staleTask = Task {
            await viewModel.load(
                query: "old",
                width: 320,
                height: 220,
                isDark: false
            )
        }
        await fulfillment(of: [staleLoadStarted], timeout: 1)

        await viewModel.load(
            query: "current",
            width: 320,
            height: 220,
            isDark: true
        )
        pendingStaleLoad?.resume(returning: stale)
        _ = await staleTask.value

        XCTAssertTrue(viewModel.image === current)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testCancellationClearsLoadingState() async {
        let snapshotStarted = expectation(description: "Map snapshot started")
        var pendingSnapshot: CheckedContinuation<UIImage?, Never>?
        let viewModel = SpeciesDictionaryRegionMapViewModel(
            dependencies: .init(
                loadSnapshot: { _, _, _, _ in
                    await withCheckedContinuation {
                        pendingSnapshot = $0
                        snapshotStarted.fulfill()
                    }
                }
            )
        )

        let task = Task {
            await viewModel.load(
                query: "United States",
                width: 320,
                height: 220,
                isDark: false
            )
        }
        await fulfillment(of: [snapshotStarted], timeout: 1)

        task.cancel()
        pendingSnapshot?.resume(returning: nil)
        _ = await task.value

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.image)
    }
}
