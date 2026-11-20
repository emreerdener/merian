import SwiftUI

/// A literal last observation, with no original-result or completion claim.
struct QueuedObservationStatusView: View {
    let state: QueuedContentViewModel.ObservationState
    var body: some View {
        VStack(spacing: 8) {
            switch state {
            case .idle:
                EmptyView()
            case .checking:
                ProgressView("Checking recorded status…")
            case .unavailable:
                Text("Recorded status couldn’t be verified. Your saved submission is preserved.")
            case .observed(let response):
                Text(response.rowExists ? "A server record was observed." : "No matching server record was observed.")
                Text(jobMessage(response.jobStatus))
                Text("The original result has not been confirmed. Checking does not run another analysis.")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    private func jobMessage(_ status: ScanObservationResponse.JobStatus?) -> String {
        switch status {
        case .processing: "Last recorded job status: processing."
        case .finalizing: "Last recorded job status: finalizing."
        case .retrying: "Last recorded job status: retrying."
        case .failedRetryable: "Last recorded job status: paused after a retryable failure."
        case .failedTerminal: "Last recorded job status: unable to complete."
        case .complete: "Last recorded job status: complete."
        case nil: "No matching job status was observed."
        }
    }
}
