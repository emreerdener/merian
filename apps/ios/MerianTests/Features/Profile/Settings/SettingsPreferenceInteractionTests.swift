import XCTest

@testable import Merian

@MainActor
final class SettingsPreferenceInteractionTests: XCTestCase {
    func testExpeditionModePersistsBeforeHardwareReconciliation() {
        var events: [String] = []
        let actions = SettingsPreferenceActions(
            reconcileHardwareConstraints: {
                events.append("reconcile")
            }
        )

        actions.updateExpeditionMode(true) { isEnabled in
            events.append("persist:\(isEnabled)")
        }

        XCTAssertEqual(events, ["persist:true", "reconcile"])
    }

    func testGeoprivacyWritesAreSerializedAndCoalesceToLatestSelection() async {
        var requestedOptionIDs: [String] = []
        var pendingFirstUpdate: CheckedContinuation<Void, Never>?
        let viewModel = GeoprivacySettingsViewModel(
            dependencies: GeoprivacySettingsDependencies(
                updatePreference: { optionID in
                    requestedOptionIDs.append(optionID)
                    if optionID == "private" {
                        await withCheckedContinuation {
                            pendingFirstUpdate = $0
                        }
                    }
                }
            )
        )

        viewModel.queuePreferenceUpdate("private")
        while pendingFirstUpdate == nil {
            await Task.yield()
        }

        viewModel.queuePreferenceUpdate("obscured")
        viewModel.queuePreferenceUpdate("open")
        XCTAssertEqual(requestedOptionIDs, ["private"])

        pendingFirstUpdate?.resume()
        while viewModel.isUpdating {
            await Task.yield()
        }

        XCTAssertEqual(requestedOptionIDs, ["private", "open"])
    }
}
