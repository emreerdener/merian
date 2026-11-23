import SwiftUI

/// Capture-specific framing controls; the profile/avatar cropper is independent.
struct CapturePhotoReviewPage: View {
    let editor: CapturePhotoEditorState
    let onRemove: () -> Void

    @ScaledMetric(relativeTo: .title2) private var headingSize = 26
    @ScaledMetric(relativeTo: .subheadline) private var instructionSize = 16

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button("Remove photo", systemImage: "trash", role: .destructive, action: onRemove)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                Spacer()
                HStack(spacing: 20) {
                    rotationButton(clockwise: false)
                    rotationButton(clockwise: true)
                }
                .padding(.horizontal, 12)
                .modifier(CaptureTrayGlass())
                Spacer()
                Color.clear.frame(width: 48, height: 48).accessibilityHidden(true)
            }
            .padding(.horizontal)
            VStack(spacing: 8) {
                Text("Review photo").font(.system(size: headingSize, weight: .semibold))
                Text(editor.selectedSourceRect == nil
                     ? "Naturebook will find the subject automatically."
                     : "Tap to reposition selection. Drag corners to adjust.")
                    .font(.system(size: instructionSize)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.horizontal)
            GeometryReader { geometry in
                let size = max(0, min(geometry.size.width, geometry.size.height))
                photo(size: size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: size, initial: true) { _, value in editor.resize(to: value) }
            }
            instructions
        }
        .frame(maxWidth: .infinity)
        .task(id: editor.candidateRevision) {
            await editor.refreshCandidates(revision: editor.candidateRevision)
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
                .onChanged { editor.drag($0.translation, ended: false) }
                .onEnded { editor.drag($0.translation, ended: true) }
                .simultaneously(with: MagnificationGesture()
                    .onChanged { editor.magnify($0, ended: false) }
                    .onEnded { editor.magnify($0, ended: true) })
                .exclusively(before: SpatialTapGesture().onEnded { editor.select(at: $0.location) }))
            .accessibilityLabel("Photo crop preview")
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
                .frame(width: 31, height: 31)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(clockwise ? "Rotate right" : "Rotate left")
        .buttonStyle(.plain)
        .disabled(!editor.allowsReframing)
    }
}
