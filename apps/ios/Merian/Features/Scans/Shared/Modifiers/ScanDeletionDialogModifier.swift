import SwiftData
import SwiftUI

@MainActor
struct ScanDeletionDialogModifier: ViewModifier {
    @Binding var isPresented: Bool

    let scanId: String?
    let modelContext: ModelContext
    let onComplete: () -> Void
    let deletionService: ScanDeletionService

    func body(content: Content) -> some View {
        content
            .alert(
                "Delete scan?",
                isPresented: $isPresented
            ) {
                Button("Delete permanently", role: .destructive) {
                    let result = deletionService.delete(
                        scanID: scanId,
                        in: modelContext
                    )
                    if result.shouldCompletePresentation {
                        onComplete()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes the discovery and its visuals. If it is published to Explore, that post, its likes, and its comments will also be permanently removed.")
            }
    }
}

extension View {
    @MainActor
    func scanDeletionDialog(
        isPresented: Binding<Bool>,
        scanId: String?,
        modelContext: ModelContext,
        deletionService: ScanDeletionService? = nil,
        onComplete: @escaping () -> Void = {}
    ) -> some View {
        modifier(
            ScanDeletionDialogModifier(
                isPresented: isPresented,
                scanId: scanId,
                modelContext: modelContext,
                onComplete: onComplete,
                deletionService: deletionService ?? ScanDeletionService()
            )
        )
    }
}
