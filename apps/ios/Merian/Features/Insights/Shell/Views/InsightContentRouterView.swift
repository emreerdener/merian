import SwiftUI

/// A dedicated structural router component that maps InsightSheetViewModel's `contentMode` into specific SwiftUI view presentations.
struct InsightContentRouterView: View {
    @Bindable var viewModel: InsightSheetViewModel
    var queuedScan: QueuedScanContext?
    var onOpenCaptureGoal: ((CaptureGoalDestination) -> Void)?
    @Environment(InferenceEngine.self) private var inferenceEngine

    private var presentationQueuedScan: QueuedScanContext? {
        viewModel.queuedContext ?? (viewModel.activeLocalRecord == nil ? queuedScan : nil)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .top) {
                switch viewModel.contentMode {
                case .analyzing:
                    // Guard: `queuedScan` (view-level property) is non-nil when this sheet is
                    // presenting a queued scan — we're just in the nil-window before onAppear
                    // sets `viewModel.queuedContext`. Show QueuedContentView immediately instead
                    // of the transient analyzing skeleton.
                    if let ctx = presentationQueuedScan {
                        QueuedContentView(viewModel: viewModel, queuedContext: ctx)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .background(Color(uiColor: .systemBackground))
                            .transition(.opacity)
                    } else {
                        AnalyzingContentView(viewModel: viewModel)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .background(Color(uiColor: .systemBackground))
                            .transition(.opacity)
                    }
                case .queued:
                    if let ctx = presentationQueuedScan {
                        QueuedContentView(viewModel: viewModel, queuedContext: ctx)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .background(Color(uiColor: .systemBackground))
                            .transition(.opacity)
                    }
                case .nonBiological:
                    if let speciesData = inferenceEngine.speciesData {
                        NonBiologicalView(
                            viewModel: viewModel,
                            species: speciesData,
                            commonName: speciesData.commonName,
                            timestamp: viewModel.activeRecordTimestamp
                        )
                        .transition(.opacity)
                    }
                case .biological:
                    BiologicalView(
                        viewModel: viewModel,
                        isSafariPresented: $viewModel.state.isSafariPresented,
                        selectedWikiURL: $viewModel.state.selectedWikiURL,
                        timestamp: viewModel.activeRecordTimestamp,
                        onOpenCaptureGoal: onOpenCaptureGoal
                    )
                    .transition(.opacity)
                }
            }
            Spacer(minLength: 40)
        }
        .animation(.easeInOut(duration: 0.35), value: viewModel.contentMode)
    }
}
