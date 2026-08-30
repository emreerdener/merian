import Foundation

struct CaptureSubmissionContextGraceResult: Sendable {
    let snapshot: CaptureSubmissionContextSnapshot?
    let timedOut: Bool
}

private actor CaptureSubmissionContextGraceGate {
    private var continuation:
        CheckedContinuation<
            CaptureSubmissionContextGraceResult,
            Never
        >?

    init(
        continuation:
            CheckedContinuation<
                CaptureSubmissionContextGraceResult,
                Never
            >
    ) {
        self.continuation = continuation
    }

    func resolve(_ result: CaptureSubmissionContextGraceResult) {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: result)
    }
}

enum CaptureSubmissionEnvironmentContextGrace {
    static func resolve(
        from task: Task<
            CaptureSubmissionContextSnapshot,
            Never
        >?,
        graceMilliseconds: Int
    ) async -> CaptureSubmissionContextGraceResult {
        guard let task else {
            return CaptureSubmissionContextGraceResult(
                snapshot: nil,
                timedOut: false
            )
        }

        return await withCheckedContinuation { continuation in
            let gate = CaptureSubmissionContextGraceGate(
                continuation: continuation
            )
            Task {
                await gate.resolve(
                    CaptureSubmissionContextGraceResult(
                        snapshot: await task.value,
                        timedOut: false
                    )
                )
            }
            Task {
                try? await Task.sleep(
                    for: .milliseconds(graceMilliseconds)
                )
                await gate.resolve(CaptureSubmissionContextGraceResult(
                    snapshot: nil,
                    timedOut: true
                ))
            }
        }
    }
}
