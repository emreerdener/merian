import SwiftUI
import SwiftData

struct ScanDeletionDialogModifier: ViewModifier {
    @Binding var isPresented: Bool
    let scanId: String?
    let modelContext: ModelContext
    let onComplete: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Delete scan",
                isPresented: $isPresented,
                titleVisibility: .visible
            ) {
                Button("Delete permanently", role: .destructive) {
                    guard let id = scanId else { return }
                    HapticManager.shared.triggerErrorThump()
                    Task {
                        await AppDIContainer.shared.scanRepository.eradicateScan(id: id, modelContext: modelContext)
                        await MainActor.run {
                            onComplete()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently remove the discovery and all associated visuals from your history.")
            }
    }
}

extension View {
    func scanDeletionDialog(
        isPresented: Binding<Bool>,
        scanId: String?,
        modelContext: ModelContext,
        onComplete: @escaping () -> Void = {}
    ) -> some View {
        self.modifier(ScanDeletionDialogModifier(
            isPresented: isPresented,
            scanId: scanId,
            modelContext: modelContext,
            onComplete: onComplete
        ))
    }
}
