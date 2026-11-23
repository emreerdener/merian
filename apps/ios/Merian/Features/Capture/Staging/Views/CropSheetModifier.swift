import SwiftUI

/// One outer owner for all staged media; selection changes stay inside this cover.
struct CropSheetModifier: ViewModifier {
    @Bindable var viewModel: CaptureWorkspaceViewModel
    var onReviewSubmit: () async -> Void = {}
    var onDismiss: () -> Void = {}
    @State private var presentedSessionID: UUID?
    @State private var didMountPresentedCover = false

    private var presentation: Binding<CaptureMediaReviewSession?> {
        Binding(get: { viewModel.mediaReviewSession }, set: { value in
            if value == nil, let session = viewModel.mediaReviewSession {
                viewModel.dismissMediaReview(sessionID: session.id)
            }
        })
    }

    func body(content: Content) -> some View {
        content.fullScreenCover(item: presentation, onDismiss: {
            guard let id = presentedSessionID ?? viewModel.mediaReviewPresentationID,
                  viewModel.finishMediaReviewDismissal(sessionID: id) else { return }
            presentedSessionID = nil
            didMountPresentedCover = false
            onDismiss()
        }) { session in
            CaptureMediaReviewView(workspace: viewModel, session: session,
                                   onSubmit: onReviewSubmit)
                .onAppear {
                    guard viewModel.mediaReviewPresentationID == session.id else { return }
                    presentedSessionID = session.id
                    didMountPresentedCover = true
                }
        }
        .onChange(of: viewModel.mediaReviewSession?.id, initial: true) { _, id in
            if let id { presentedSessionID = id } else if !didMountPresentedCover,
                    let pendingID = viewModel.mediaReviewPresentationID,
                    viewModel.finishMediaReviewDismissal(sessionID: pendingID) {
                // No mounted presentation owns an animation completion.
                presentedSessionID = nil
                onDismiss()
            }
        }
    }
}
