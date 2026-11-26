import SwiftUI

/// Only corner targets intercept dragging. The clear interior and edges leave
/// one-finger panning on the photo, as specified by the review design.
struct CapturePhotoSelectionOverlay: View {
    let editor: CapturePhotoEditorState
    @GestureState private var isResizing = false

    var body: some View {
        if editor.allowsManualSelection, let rect = editor.selectionViewportRect {
            ZStack(alignment: .topLeading) {
                brackets(in: rect)
                    .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                ForEach(CapturePhotoSelectionGeometry.Corner.allCases, id: \.self) { corner in
                    handle(corner, rect: rect)
                }
            }
            .frame(width: editor.displaySize, height: editor.displaySize)
            .coordinateSpace(name: "photo-selection")
            .onChange(of: isResizing) { _, active in if !active { editor.endSelectionGesture() } }
            .onDisappear { editor.endSelectionGesture() }
        }
    }

    private func handle(_ corner: CapturePhotoSelectionGeometry.Corner, rect: CGRect) -> some View {
        let point = position(corner, rect: rect)
        return Color.clear
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("photo-selection"))
                .updating($isResizing) { _, active, _ in active = true }
                .onChanged { editor.dragSelection(corner: corner, translation: $0.translation, ended: false) }
                .onEnded { editor.dragSelection(corner: corner, translation: $0.translation, ended: true) })
            .position(point)
            .accessibilityElement()
            .accessibilityLabel(label(corner))
            .accessibilityIdentifier("photoSelection.\(corner)")
            .accessibilityAction(named: "Move left") { move(corner, point: point, dx: -10, dy: 0) }
            .accessibilityAction(named: "Move right") { move(corner, point: point, dx: 10, dy: 0) }
            .accessibilityAction(named: "Move up") { move(corner, point: point, dx: 0, dy: -10) }
            .accessibilityAction(named: "Move down") { move(corner, point: point, dx: 0, dy: 10) }
    }

    private func move(_ corner: CapturePhotoSelectionGeometry.Corner, point: CGPoint, dx: CGFloat, dy: CGFloat) {
        editor.resizeSelection(corner: corner, to: CGPoint(x: point.x + dx, y: point.y + dy))
    }

    private func position(_ corner: CapturePhotoSelectionGeometry.Corner, rect: CGRect) -> CGPoint {
        let left = corner == .topLeft || corner == .bottomLeft
        let top = corner == .topLeft || corner == .topRight
        return CGPoint(x: left ? rect.minX : rect.maxX, y: top ? rect.minY : rect.maxY)
    }

    private func label(_ corner: CapturePhotoSelectionGeometry.Corner) -> String {
        switch corner {
        case .topLeft: return "Selection top left corner"
        case .topRight: return "Selection top right corner"
        case .bottomLeft: return "Selection bottom left corner"
        case .bottomRight: return "Selection bottom right corner"
        }
    }

    private func brackets(in rect: CGRect) -> Path {
        let length = min(24, min(rect.width, rect.height) / 3)
        let radius = min(10, length / 2)
        return Path { path in
            for corner in CapturePhotoSelectionGeometry.Corner.allCases {
                let point = position(corner, rect: rect)
                let dx: CGFloat = corner == .topLeft || corner == .bottomLeft ? 1 : -1
                let dy: CGFloat = corner == .topLeft || corner == .topRight ? 1 : -1
                path.move(to: CGPoint(x: point.x + dx * length, y: point.y))
                path.addLine(to: CGPoint(x: point.x + dx * radius, y: point.y))
                path.addQuadCurve(to: CGPoint(x: point.x, y: point.y + dy * radius), control: point)
                path.addLine(to: CGPoint(x: point.x, y: point.y + dy * length))
            }
        }
    }
}
