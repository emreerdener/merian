#if DEBUG
import SwiftUI

extension UITestSeedCoordinator {
    static var photoSelectionReviewEnabled: Bool {
        isEnabled && TestExecutionCoordinator.isRunningUITests
            && ProcessInfo.processInfo.arguments.contains("-seedPhotoSelectionReview")
    }
}

/// Gesture-only harness for the production editor. It does not qualify a
/// submission owner or enable selection in the ordinary Debug workspace.
struct PhotoSelectionUITestPresentation: ViewModifier {
    @State private var editor: CapturePhotoEditorState?

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: Binding(get: { editor != nil }, set: { if !$0 { editor = nil } })) {
            if let editor {
                VStack(spacing: 0) {
                    CapturePhotoReviewPage(editor: editor, onRemove: {})
                    Text(sourceDescription(editor))
                        .font(.caption2).accessibilityIdentifier("PhotoSelectionSource")
                        .accessibilityValue("scale=\(editor.scale) offset=\(editor.offset) viewport=\(editor.displaySize)")
                }
                .background(.black).preferredColorScheme(.dark)
            }
        }
        .task {
            guard UITestSeedCoordinator.photoSelectionReviewEnabled, editor == nil else { return }
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400), format: format).image { context in
                UIColor.systemBlue.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
            }
            editor = CapturePhotoEditorState(original: IdentifiableImage(image: image), allowsManualSelection: true)
        }
    }

    private func sourceDescription(_ editor: CapturePhotoEditorState) -> String {
        guard let rect = editor.selectedSourceRect else { return "none" }
        return [rect.minX, rect.minY, rect.width, rect.height].map { String(format: "%.6f", Double($0)) }.joined(separator: ",")
    }
}
#endif
