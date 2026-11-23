import Foundation
import Observation

/// Autosaved draft values may outlive an auth-refresh presentation, but never
/// their observation identity. This carries no session or mutation authority.
struct CaptureInitialNotesRecovery {
    let identity: CaptureInitialDraftSession.Identity
    let contexts: [StagedObservationContext]
    let progress: DescribePromptViewModel.Progress?
}

/// A closed session stays occupied until its matching outer dismissal finishes.
@MainActor
@Observable
final class CaptureFieldNotesSession: Identifiable {
    struct OpenIntent {
        let draftGeneration: UUID
        let accountID: UUID?
    }
    let id = UUID()
    let draftGeneration: UUID
    let accountID: UUID?
    let prompts: DescribePromptViewModel
    let input: DescribeInputViewModel
    var isPresented = true
    var isSubmitting = false
    var isDictationRequested = false
    var errorMessage: String?

    init(draftGeneration: UUID, accountID: UUID?, flow: DescribePromptFlow,
         progress: DescribePromptViewModel.Progress?,
         inputDependencies: DescribeInputViewModel.Dependencies) {
        self.draftGeneration = draftGeneration
        self.accountID = accountID
        prompts = DescribePromptViewModel()
        input = DescribeInputViewModel(dependencies: inputDependencies)
        prompts.configure(for: flow)
        if let progress { prompts.restore(progress) }
    }

    func stopInput() {
        input.stopAll(isRequested: isDictationRequested, isRecording: false,
                      isStarting: false, onRequestEnded: { self.isDictationRequested = false })
    }
}
