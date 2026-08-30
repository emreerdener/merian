/// Generation fence shared by asynchronous audio start, resume, and countdown
/// work. A token may publish state only while it remains current.
struct AudioCaptureTransitionToken: Equatable, Sendable {
    fileprivate let generation: UInt64
}

struct AudioCaptureTransitionState {
    private var generation: UInt64 = 0
    private var currentToken: AudioCaptureTransitionToken?

    mutating func begin() -> AudioCaptureTransitionToken {
        generation &+= 1
        let token = AudioCaptureTransitionToken(generation: generation)
        currentToken = token
        return token
    }

    mutating func invalidate() {
        generation &+= 1
        currentToken = nil
    }

    func isCurrent(_ token: AudioCaptureTransitionToken) -> Bool {
        currentToken == token
    }
}
