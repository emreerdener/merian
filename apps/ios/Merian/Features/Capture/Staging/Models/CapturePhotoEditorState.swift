import Observation
import UIKit

/// UI-only crop state. It never becomes evidence until Shell accepts the commit.
@MainActor @Observable
final class CapturePhotoEditorState {
    let original: IdentifiableImage
    private(set) var displaySize: CGFloat = 0
    private(set) var scale: CGFloat
    private(set) var offset: CGSize
    private(set) var quarterTurns: Int
    private(set) var hasEdits = false
    private(set) var hasSelectionEdits = false
    private(set) var selectedSourceRect: CGRect?
    private(set) var candidateRevision = UUID()
    private(set) var candidates: [CGRect] = []
    /// The submission owner enables this only after the evidence contract is ready.
    let allowsManualSelection: Bool
    private(set) var usesFullAspect: Bool
    var allowsReframing: Bool { original.allowsReframing }
    private(set) var renderedImage: UIImage
    private var didInitialize = false
    private var dragOrigin: CGSize?
    private var zoomOrigin: CGFloat?
    private var selectionDragOrigin: CGRect?

    init(original: IdentifiableImage, allowsManualSelection: Bool = false, selectedSourceRect: CGRect? = nil,
         usesFullAspect: Bool = false) {
        self.original = original
        self.allowsManualSelection = allowsManualSelection
        self.usesFullAspect = usesFullAspect
        self.selectedSourceRect = selectedSourceRect ?? original.manualSourceSelection?.rect
        scale = original.lastCropScale
        offset = original.lastCropOffset
        let turns = ImageCropProcessor.normalizedQuarterTurns(original.lastCropQuarterTurns)
        quarterTurns = turns
        renderedImage = ImageCropProcessor.rotatedImage(original.image, quarterTurns: turns)
    }

    func resize(to size: CGFloat) {
        guard size.isFinite, size > 0 else { return }
        if size != displaySize { candidateRevision = UUID(); candidates = [] }
        let priorSize = displaySize > 0 ? displaySize : original.lastCropDisplaySize
        if let priorSize, priorSize > 0 {
            offset = CGSize(width: offset.width * size / priorSize, height: offset.height * size / priorSize)
        }
        displaySize = size
        if !didInitialize, original.lastCropDisplaySize == nil, let center = original.initialCameraVerticalCenter,
           let initial = ImageCropProcessor.initialSquareCropOffset(imageSize: original.image.size,
                displaySize: size, verticalCenterFraction: center) {
            offset = initial
        }
        didInitialize = true
        offset = clamp(offset)
        dragOrigin = nil
        zoomOrigin = nil
        selectionDragOrigin = nil
    }

    func drag(_ translation: CGSize, ended: Bool) {
        guard allowsReframing, displaySize > 0, translation.width.isFinite, translation.height.isFinite else { return }
        if translation != .zero { beginFraming() }
        let origin = dragOrigin ?? offset
        dragOrigin = origin
        offset = clamp(CGSize(width: origin.width + translation.width, height: origin.height + translation.height))
        if offset != origin { hasEdits = true }
        if ended { endDragGesture() }
    }

    func magnify(_ value: CGFloat, ended: Bool) {
        guard allowsReframing, value.isFinite, value > 0 else { return }
        if value != 1 { beginFraming() }
        let origin = zoomOrigin ?? scale
        zoomOrigin = origin
        scale = max(1, origin * value)
        offset = clamp(offset)
        if scale != origin { hasEdits = true }
        if ended { endMagnifyGesture() }
    }

    func endDragGesture() {
        guard dragOrigin != nil else { return }
        dragOrigin = nil
        finishFramingGesture()
    }

    func endMagnifyGesture() {
        guard zoomOrigin != nil else { return }
        zoomOrigin = nil
        finishFramingGesture()
    }

    // A GestureState reset may settle first. Late terminal callbacks must not
    // apply their absolute translation/magnification again from the new origin.
    // Direct drag/magnify commands remain available to accessibility actions.
    func finishDragGesture(_ translation: CGSize) {
        guard dragOrigin != nil else { return }
        drag(translation, ended: true)
    }

    func finishMagnifyGesture(_ value: CGFloat) {
        guard zoomOrigin != nil else { return }
        magnify(value, ended: true)
    }

    func cancelFramingGestures() {
        guard dragOrigin != nil || zoomOrigin != nil else { return }
        dragOrigin = nil
        zoomOrigin = nil
        finishFramingGesture()
    }

    func endSelectionGesture() { selectionDragOrigin = nil }

    func rotate(clockwise: Bool) {
        guard allowsReframing else { return }
        beginFraming()
        let turn = clockwise ? 1 : -1
        quarterTurns = ImageCropProcessor.normalizedQuarterTurns(quarterTurns + turn)
        renderedImage = ImageCropProcessor.rotatedImage(original.image, quarterTurns: quarterTurns)
        offset = clamp(ImageCropProcessor.rotatedOffset(offset, quarterTurns: turn))
        dragOrigin = nil
        zoomOrigin = nil
        hasEdits = true
        finishFramingGesture()
    }

    func generateCrop() async -> Data {
        guard allowsReframing, displaySize > 0 else { return Data() }
        return await ImageCropProcessor.generateCrop(image: original.image, displaySize: displaySize,
            scale: scale, currentScale: 1, offset: offset, currentOffset: .zero, quarterTurns: quarterTurns)
    }

    private func clamp(_ proposed: CGSize) -> CGSize {
        let ratio = renderedImage.size.width / max(1, renderedImage.size.height)
        let maxX = max(0, (displaySize * max(1, ratio) * scale - displaySize) / 2)
        let maxY = max(0, (displaySize * max(1, 1 / max(ratio, .leastNonzeroMagnitude)) * scale - displaySize) / 2)
        return CGSize(width: min(max(proposed.width, -maxX), maxX),
                      height: min(max(proposed.height, -maxY), maxY))
    }

    var selectionGeometry: CapturePhotoSelectionGeometry {
        .init(sourceSize: original.image.size, viewportSize: displaySize,
              scale: scale, offset: offset, quarterTurns: quarterTurns, fitsFullAspect: usesFullAspect)
    }

    var selectionViewportRect: CGRect? {
        selectedSourceRect.flatMap { selectionGeometry.viewportRect(for: $0) }
    }

    var sourceSelection: NormalizedImageFocusRegion? {
        selectedSourceRect.map { .init(x: $0.minX, y: $0.minY, width: $0.width,
                                      height: $0.height, source: .userSelection) }
    }

    func select(at point: CGPoint) {
        guard allowsManualSelection,
              let rect = selectionGeometry.selection(at: point, existing: selectedSourceRect,
                                                       candidates: candidates) else { return }
        selectedSourceRect = rect
        hasSelectionEdits = true
    }

    func resizeSelection(corner: CapturePhotoSelectionGeometry.Corner, to point: CGPoint) {
        guard allowsManualSelection, let current = selectedSourceRect,
              let rect = selectionGeometry.resized(current, corner: corner, to: point) else { return }
        selectedSourceRect = rect
        hasSelectionEdits = true
    }

    func dragSelection(corner: CapturePhotoSelectionGeometry.Corner, translation: CGSize, ended: Bool) {
        guard allowsManualSelection, let current = selectedSourceRect else { return }
        let origin = selectionDragOrigin ?? current
        selectionDragOrigin = origin
        defer { if ended { selectionDragOrigin = nil } }
        guard let rect = selectionGeometry.viewportRect(for: origin) else { return }
        let left = corner == .topLeft || corner == .bottomLeft
        let top = corner == .topLeft || corner == .topRight
        let point = CGPoint(x: (left ? rect.minX : rect.maxX) + translation.width,
                            y: (top ? rect.minY : rect.maxY) + translation.height)
        guard let resized = selectionGeometry.resized(origin, corner: corner, to: point) else { return }
        if resized != current { selectedSourceRect = resized; hasSelectionEdits = true }
    }

    func clearSelection() {
        guard allowsManualSelection, selectedSourceRect != nil else { return }
        selectedSourceRect = nil
        selectionDragOrigin = nil
        hasSelectionEdits = true
    }

    /// Results never create or replace a selection. A late detection pass from
    /// a former editor/transform cannot influence a later tap.
    func acceptCandidates(_ rectangles: [CGRect], revision: UUID) {
        guard allowsManualSelection, revision == candidateRevision else { return }
        candidates = rectangles.filter { selectionGeometry.finalCropRect(for: $0) != nil }
    }

    /// A bounded upright thumbnail keeps candidate coordinates in the immutable
    /// source space. Detection only assists a later tap; it never selects for us.
    func refreshCandidates(revision: UUID) async {
        guard allowsManualSelection, displaySize > 0, revision == candidateRevision,
              !Task.isCancelled else { return }
        let source = original.image
        let factor = min(1, 512 / max(source.size.width, source.size.height))
        let size = CGSize(width: source.size.width * factor, height: source.size.height * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let thumbnail = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = thumbnail.jpegData(compressionQuality: 0.85) else { return }
        let result = await ImageFocusEngine.detectAndDrain(in: data)
        guard !Task.isCancelled, case .candidates(let found) = result else { return }
        let rectangles = found.compactMap { candidate -> CGRect? in
            let bounds = candidate.boundingBox
            guard candidate.confidence.isFinite, candidate.confidence >= 0.5 else { return nil }
            return CGRect(x: bounds.minX, y: 1 - bounds.maxY, width: bounds.width, height: bounds.height)
        }
        acceptCandidates(rectangles, revision: revision)
    }

    private func finishFramingGesture() {
        // Pinch and pan can overlap. Judge exclusion only after both recognizers
        // settle, so an intermediate crop cannot discard a recoverable selection.
        guard dragOrigin == nil, zoomOrigin == nil else { return }
        candidateRevision = UUID()
        candidates = []
        guard let rect = selectedSourceRect, selectionGeometry.finalCropRect(for: rect) == nil else { return }
        selectedSourceRect = nil
        hasSelectionEdits = true
        UIAccessibility.post(notification: .announcement, argument: "Selection cleared because the crop changed.")
    }

    private func beginFraming() {
        if dragOrigin == nil, zoomOrigin == nil {
            candidateRevision = UUID()
            candidates = []
        }
        guard usesFullAspect else { return }
        usesFullAspect = false
        hasEdits = true
    }
}
