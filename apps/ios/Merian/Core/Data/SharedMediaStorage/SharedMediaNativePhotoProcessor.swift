import Foundation
import UIKit

/// Memory-only output assertions, not a pair publication or file capability.
/// Only the sealed native plan may admit these against its exact active attempt.
struct SharedMediaNativePreparedOutputs: Sendable {
    let attempt: SharedMediaNativePreparationAttempt
    let intent: SharedMediaNativeDerivativeIntent
    let ai: Data
    let display: Data
}

/// Called by the existing file-owning IO actor after reservation and source
/// verification. It creates no scratch file and never constructs a repository.
enum SharedMediaNativePhotoProcessor {
    static func prepare(url: URL, attempt: SharedMediaNativePreparationAttempt, focusFactory: ImageFocusWorkFactory) async throws -> SharedMediaNativePreparedOutputs {
        try attempt.validate(); try Task.checkCancellation()
        let output = try await OriginalPhotoRenderer.render(.file(url), recipe: attempt.recipe)
        let ai = output.inference, display = output.display
        let manualFocus = output.manualFocus
        let aiInput = try SharedMediaDerivativeWorkFiles.prepare(ai, role: .aiInput)
        let displayInput = try SharedMediaDerivativeWorkFiles.prepare(display, role: .display)
        // Unlike the interactive Capture façade, this call waits for actual
        // worker termination even when timeout/cancellation fixes a nil outcome.
        let focus: NormalizedImageFocusRegion?
        if let manualFocus { focus = manualFocus } else {
            focus = await ImageFocusEngine.detectAndDrain(in: ai, factory: focusFactory).region
        }
        try Task.checkCancellation()
        let intent = SharedMediaNativeDerivativeIntent(format: .intent, preparation: try .init(attempt: attempt),
            pairID: UUID(), nonce: UUID(), previousPairID: nil, ai: aiInput, display: displayInput, focus: focus)
        _ = try intent.encoded()
        return .init(attempt: attempt, intent: intent, ai: ai, display: display)
    }

}
