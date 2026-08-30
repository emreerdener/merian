import SwiftUI

struct ExternalImageImportRetryModifier: ViewModifier {
    let viewModel: CaptureWorkspaceViewModel
    let stagedItemCount: Int
    let stagedCaptureLimit: Int
    let canStartProScan: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: stagedItemCount) { oldCount, newCount in
                if newCount < oldCount {
                    viewModel.importPendingExternalImageIfPossible()
                }
            }
            .onChange(of: stagedCaptureLimit) { oldLimit, newLimit in
                if newLimit > oldLimit {
                    viewModel.importPendingExternalImageIfPossible()
                }
            }
            .onChange(of: canStartProScan) { _, _ in
                viewModel.importPendingExternalImageIfPossible()
            }
    }
}
