import SwiftUI

extension InsightSheetView {
    @ViewBuilder
    var mainContentStack: some View {
        InsightContentView(
            viewModel: viewModel,
            queuedScan: queuedScan,
            onOpenFieldTripOverview: openFieldTripOverview
        )
            .merianSystemFeedback(
                toast: $viewModel.state.toastMessage,
                toastAction: toastActionBinding
            )
            .ignoresSafeArea(edges: .top)
    }

    private func openFieldTripOverview(_ destination: InsightFieldTripOverviewDestination) {
        if presentationStyle.isEmbedded, let onOpenFieldTripOverview {
            onOpenFieldTripOverview(destination)
            return
        }

        selectedFieldTripOverviewDestination = destination
    }

    @MainActor
    private var toastActionBinding: Binding<(() -> Void)?> {
        Binding(
            get: {
                guard let action = viewModel.toastAction else { return nil }
                guard !allowsExplorePresentation,
                      viewModel.state.toastMessage?.action?.id == .viewCommunityRequest,
                      let requestId = viewModel.state.sharedCommunityIdentificationRequestId,
                      let scanId = viewModel.presentedLocalRecordScanId
                else {
                    return action
                }
                let generation = viewModel.scanBoundActionGeneration

                return {
                    guard viewModel.isPresentingLocalRecord(
                        scanId: scanId,
                        generation: generation
                    ),
                          viewModel.state.sharedCommunityIdentificationRequestId?
                            .caseInsensitiveCompare(requestId) == .orderedSame else {
                        return
                    }
                    if let onOpenCommunityIdentificationRequest {
                        onOpenCommunityIdentificationRequest(requestId)
                    } else {
                        dependencies.requestCommunityIdentification(requestId)
                    }
                }
            },
            set: { viewModel.toastAction = $0 }
        )
    }
}
