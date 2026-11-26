import SwiftUI

/// Capture-specific framing controls; the profile/avatar cropper is independent.
struct CapturePhotoReviewPage: View {
    let editor: CapturePhotoEditorState
    let onRemove: () -> Void

    @ScaledMetric(relativeTo: .title2) private var headingSize = 26
    @ScaledMetric(relativeTo: .subheadline) private var instructionSize = 16
    @GestureState private var isDragging = false
    @GestureState private var isMagnifying = false

    var body: some View {
        VStack(spacing: 0) {
            topToolbar
            CapturePhotoReviewContentLayout {
                VStack(spacing: 8) {
                    Text("Review photo").font(.system(size: headingSize, weight: .semibold))
                    Text(editor.selectedSourceRect == nil
                         ? "Naturebook will find the subject automatically."
                         : "Tap to reposition selection. Drag corners to adjust.")
                        .font(.system(size: instructionSize)).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                GeometryReader { geometry in
                    let size = max(0, min(geometry.size.width, geometry.size.height))
                    photo(size: size)
                        .onChange(of: size, initial: true) { _, value in editor.resize(to: value) }
                }
                instructions
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: editor.candidateRevision) {
            await editor.refreshCandidates(revision: editor.candidateRevision)
        }
        .onChange(of: isDragging) { _, active in if !active { editor.endDragGesture() } }
        .onChange(of: isMagnifying) { _, active in if !active { editor.endMagnifyGesture() } }
        .onDisappear { editor.cancelFramingGestures() }
    }

    private var topToolbar: some View {
        HStack(spacing: 0) {
            rotationButton(clockwise: false)
            rotationButton(clockwise: true)
        }
        .frame(width: CaptureModeSelectorStyle.controlWidth, height: CaptureModeSelectorStyle.controlHeight)
        .modifier(CaptureTrayGlass())
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) {
            CaptureStagingCancelButton(action: onRemove)
                .accessibilityLabel("Remove photo")
                .padding(.leading, 20)
        }
    }

    private func photo(size: CGFloat) -> some View {
        Image(uiImage: editor.renderedImage)
            .resizable().aspectRatio(contentMode: editor.usesFullAspect ? .fit : .fill)
            .frame(width: size, height: size)
            .scaleEffect(editor.scale)
            .offset(editor.offset)
            .frame(width: size, height: size)
            .clipped()
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 10)
                .updating($isDragging) { _, active, _ in active = true }
                .onChanged { editor.drag($0.translation, ended: false) }
                .onEnded { editor.finishDragGesture($0.translation) }
                .simultaneously(with: MagnificationGesture()
                    .updating($isMagnifying) { _, active, _ in active = true }
                    .onChanged { editor.magnify($0, ended: false) }
                    .onEnded { editor.finishMagnifyGesture($0) })
                .exclusively(before: SpatialTapGesture().onEnded { editor.select(at: $0.location) }))
            .accessibilityLabel("Photo crop preview")
            .accessibilityIdentifier("CapturePhotoPreview")
            .overlay { CapturePhotoSelectionOverlay(editor: editor) }
            .accessibilityActions {
                if editor.allowsReframing {
                    Button("Zoom in") { editor.magnify(1.1, ended: true) }
                    Button("Zoom out") { editor.magnify(1 / 1.1, ended: true) }
                    Button("Move left") { editor.drag(.init(width: -20, height: 0), ended: true) }
                    Button("Move right") { editor.drag(.init(width: 20, height: 0), ended: true) }
                    Button("Move up") { editor.drag(.init(width: 0, height: -20), ended: true) }
                    Button("Move down") { editor.drag(.init(width: 0, height: 20), ended: true) }
                }
                if editor.allowsManualSelection {
                    Button("Select subject") {
                        editor.select(at: CGPoint(x: size / 2, y: size / 2))
                    }
                }
            }
    }

    @ViewBuilder private var instructions: some View {
        if editor.allowsManualSelection, editor.selectedSourceRect != nil {
            Button { editor.clearSelection() } label: {
                Text("Clear selection").frame(minHeight: 44).contentShape(Rectangle())
            }
                .buttonStyle(.bordered).buttonBorderShape(.capsule)
                .tint(.white)
                .accessibilityIdentifier("clearPhotoSelection")
        } else {
            Text(!editor.allowsReframing
                 ? (editor.allowsManualSelection ? "Tap to select. Add a replacement photo to change framing." : "Add a replacement photo to change framing.")
                 : editor.allowsManualSelection ? "Pinch to zoom, drag to move, tap to select" : "Pinch to zoom, drag to move")
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private func rotationButton(clockwise: Bool) -> some View {
        Button {
            editor.rotate(clockwise: clockwise)
        } label: {
            Image(clockwise ? "capture-review-rotate-right" : "capture-review-rotate-left")
                .resizable()
                .scaledToFit()
                .frame(width: CaptureModeSelectorStyle.symbolPointSize, height: CaptureModeSelectorStyle.symbolPointSize)
                .frame(width: CaptureModeSelectorStyle.controlWidth / 2, height: CaptureModeSelectorStyle.controlHeight)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(clockwise ? "Rotate right" : "Rotate left")
        .buttonStyle(.plain)
        .disabled(!editor.allowsReframing)
    }
}

/// Measure text before sizing the square, so Dynamic Type can shrink the preview
/// without separating its helper or pinning the heading to the toolbar.
private struct CapturePhotoReviewContentLayout: Layout {
    private let spacing: CGFloat = 16

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 320, height: 640))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let textProposal = ProposedViewSize(width: bounds.width, height: nil)
        let heading = subviews[0].sizeThatFits(textProposal)
        let helper = subviews[2].sizeThatFits(textProposal)
        let side = max(0, min(bounds.width, bounds.height - heading.height - helper.height - spacing * 3))
        let minimumTop = heading.height + spacing * 2
        let maximumTop = max(minimumTop, bounds.height - side - helper.height - spacing)
        let photoTop = min(maximumTop, max(minimumTop, (bounds.height - side) / 2))

        subviews[0].place(at: CGPoint(x: bounds.midX, y: bounds.minY + photoTop / 2),
            anchor: .center, proposal: ProposedViewSize(width: bounds.width, height: heading.height))
        subviews[1].place(at: CGPoint(x: bounds.midX, y: bounds.minY + photoTop),
            anchor: .top, proposal: ProposedViewSize(width: side, height: side))
        subviews[2].place(at: CGPoint(x: bounds.midX, y: bounds.minY + photoTop + side + spacing),
            anchor: .top, proposal: ProposedViewSize(width: bounds.width, height: helper.height))
    }
}
