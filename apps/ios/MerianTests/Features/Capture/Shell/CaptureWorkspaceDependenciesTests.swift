import XCTest

@testable import Merian

@MainActor
final class CaptureWorkspaceDependenciesTests: XCTestCase {
    func testViewModelUsesInjectedFeedbackWithoutRunningDisabledPrewarm() {
        let spy = CaptureWorkspaceDependencySpy()
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dependencies = CaptureWorkspaceDependencies(
            scan: .live(diContainer: AppDIContainer.shared),
            submission: .live(diContainer: AppDIContainer.shared),
            prepareImage: { _ in nil },
            prepareHistoricalAudio: { _ in nil },
            externalImageImports: ExternalImageImportStore(rootURL: rootURL),
            downloadRefinementImage: { _ in nil },
            prewarmConnections: {
                spy.prewarmCount += 1
            },
            sharedExplorePostId: { _ in "post-id" },
            captureGoalAccountId: { $0?.uuidString.lowercased() },
            feedback: CaptureWorkspaceFeedback(
                selection: { spy.selectionSources.append($0) },
                sheet: { spy.sheetSources.append($0) },
                medium: { spy.mediumCount += 1 },
                error: { spy.errorCount += 1 }
            )
        )
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: AppDIContainer.shared,
            dependencies: dependencies,
            prewarmHeadersOnInit: false
        )

        viewModel.triggerSelectionFeedback(source: "capture.test.selection")
        viewModel.triggerSheetFeedback(source: "capture.test.sheet")
        viewModel.triggerSheetFeedback()
        viewModel.triggerMediumFeedback()
        viewModel.triggerErrorFeedback()

        XCTAssertEqual(spy.prewarmCount, 0)
        XCTAssertEqual(spy.selectionSources, ["capture.test.selection"])
        XCTAssertEqual(
            spy.sheetSources,
            ["capture.test.sheet", nil]
        )
        XCTAssertEqual(spy.mediumCount, 1)
        XCTAssertEqual(spy.errorCount, 1)

        let userId = UUID(
            uuidString: "00000000-0000-4000-8000-000000000779"
        )!
        XCTAssertEqual(
            viewModel.captureGoalAccountId(for: userId),
            userId.uuidString.lowercased()
        )
    }
}

@MainActor
private final class CaptureWorkspaceDependencySpy {
    var prewarmCount = 0
    var selectionSources: [String] = []
    var sheetSources: [String?] = []
    var mediumCount = 0
    var errorCount = 0
}
