import SwiftUI

enum CaptureWorkspacePresentationBindings {
    static func isPresented<Item>(
        by item: Binding<Item?>
    ) -> Binding<Bool> {
        Binding(
            get: { item.wrappedValue != nil },
            set: { isPresented in
                if !isPresented {
                    item.wrappedValue = nil
                }
            }
        )
    }

    @MainActor
    static func offlineToast(
        for viewModel: CaptureWorkspaceViewModel
    ) -> Binding<ToastPayload?> {
        Binding(
            get: { viewModel.offlineToastMessage },
            set: { viewModel.offlineToastMessage = $0 }
        )
    }

    @MainActor
    static func restoreBottomChrome(
        isKeyboardVisible: Binding<Bool>,
        animated: Bool
    ) {
        guard isKeyboardVisible.wrappedValue else { return }
        let update = {
            isKeyboardVisible.wrappedValue = false
        }

        if animated {
            withAnimation(.easeOut(duration: 0.18), update)
        } else {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction, update)
        }
    }
}
