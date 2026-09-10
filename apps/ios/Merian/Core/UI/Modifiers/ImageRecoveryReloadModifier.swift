import SwiftUI

/// Retained image state must reload when stronger evidence changes its source.
/// The stream follows view lifetime and only signals changes to these URLs.
private struct ImageRecoveryReloadModifier: ViewModifier {
    let imagePath: String?
    let fallbackURL: String?
    @Binding var revision: UInt64

    func body(content: Content) -> some View {
        content.task(id: [imagePath, fallbackURL]) {
            for await _ in LocalScanMediaRecoveryResolver.recoveryChanges(
                imagePath: imagePath, fallbackURL: fallbackURL
            ) {
                guard !Task.isCancelled else { return }
                revision = LocalScanMediaRecoveryResolver.cacheRevision(
                    imagePath: imagePath, fallbackURL: fallbackURL
                )
            }
        }
    }
}

extension View {
    /// Include `revision` in the image-loading task's identity and discard a
    /// cancelled load's result before assigning it to visible state.
    func reloadOnImageRecovery(
        imagePath: String?,
        fallbackURL: String? = nil,
        revision: Binding<UInt64>
    ) -> some View {
        modifier(ImageRecoveryReloadModifier(
            imagePath: imagePath, fallbackURL: fallbackURL, revision: revision
        ))
    }
}
