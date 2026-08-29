import SwiftData
import SwiftUI

struct NonBiologicalScansView: View {
    let scans: [LocalScanRecord]

    @Environment(\.modelContext) private var modelContext

    @State private var viewModel: NonBiologicalScansViewModel
    @State private var scanToReanalyze: String?
    @State private var scanToDelete: String?
    @State private var showDeleteConfirmation = false
    @State private var showClearAllConfirmation = false

    init(
        scans: [LocalScanRecord],
        dependencies: NonBiologicalDependencies? = nil
    ) {
        self.scans = scans
        _viewModel = State(
            initialValue: NonBiologicalScansViewModel(
                scans: scans,
                dependencies: dependencies
            )
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if viewModel.scans.isEmpty {
                    EmptyStateView(
                        iconName:
                            NonBiologicalScansPresentation.emptyIconName,
                        title: NonBiologicalScansPresentation.emptyTitle,
                        message: NonBiologicalScansPresentation.emptyMessage
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: geometry.size.height
                    )
                } else {
                    NonBiologicalRetentionBanner()

                    ScansGrid(
                        scans: viewModel.scans,
                        onSelect: { scan in
                            scanToReanalyze = scan.id
                        },
                        onDelete: { scan in
                            scanToDelete = scan.id
                            showDeleteConfirmation = true
                        }
                    ) { scan in
                        Button {
                            scanToReanalyze = scan.id
                        } label: {
                            Label(
                                NonBiologicalScansPresentation
                                    .reanalysisAction,
                                systemImage:
                                    "leaf.arrow.triangle.circlepath"
                            )
                        }
                    }
                    .allowsHitTesting(!viewModel.isClearingAll)
                    .accessibilityHidden(viewModel.isClearingAll)
                }
            }
        }
        .overlay {
            if viewModel.isClearingAll {
                NonBiologicalClearingProgressView()
            }
        }
        .merianSystemFeedback(
            toast: $viewModel.toastMessage,
            showsAchievementToasts: false
        )
        .task(id: refreshIdentity) {
            viewModel.refresh(scans: scans)
        }
        .task {
            await viewModel.purgeExpired(
                in: modelContext.container
            )
        }
        .navigationTitle(NonBiologicalScansPresentation.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !viewModel.scans.isEmpty {
                    Button {
                        showClearAllConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .buttonBorderShape(.circle)
                    .disabled(viewModel.isClearingAll)
                }
            }
        }
        .alert(
            NonBiologicalCorrectionReanalysis.confirmationTitle,
            isPresented: Binding(
                get: { scanToReanalyze != nil },
                set: { if !$0 { scanToReanalyze = nil } }
            )
        ) {
            Button(
                NonBiologicalCorrectionReanalysis.secondaryAction,
                role: .cancel
            ) { }
            Button(NonBiologicalCorrectionReanalysis.primaryAction) {
                if let scanID = scanToReanalyze {
                    viewModel.requestReanalysis(scanID: scanID)
                }
            }
        } message: {
            Text(NonBiologicalCorrectionReanalysis.confirmationMessage)
        }
        .scanDeletionDialog(
            isPresented: $showDeleteConfirmation,
            scanId: scanToDelete,
            modelContext: modelContext
        ) {
            scanToDelete = nil
            viewModel.didDeleteSingleScan()
        }
        .alert(
            viewModel.clearAllConfirmationTitle,
            isPresented: $showClearAllConfirmation
        ) {
            Button(
                NonBiologicalScansPresentation.deleteAllAction,
                role: .destructive
            ) {
                Task {
                    await viewModel.clearAll(
                        in: modelContext.container
                    )
                }
            }
            Button(
                NonBiologicalScansPresentation.cancelAction,
                role: .cancel
            ) { }
        } message: {
            Text(NonBiologicalScansPresentation.deleteAllMessage)
        }
    }

    private var refreshIdentity: NonBiologicalScansRefreshIdentity {
        viewModel.refreshIdentity(scans: scans)
    }
}
