import CoreGraphics

/// An immutable Core Graphics image transferred across structured-concurrency
/// boundaries without introducing a UIKit image into worker results.
///
/// `CGImage` is an immutable Core Foundation value. The unchecked conformance
/// exists only because the supported SDK baseline does not import it as
/// `Sendable`; this wrapper must not acquire mutable reference state.
struct SendableCGImage: @unchecked Sendable {
    let image: CGImage
}
