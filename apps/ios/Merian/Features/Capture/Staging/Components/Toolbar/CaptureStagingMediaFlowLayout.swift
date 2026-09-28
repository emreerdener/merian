import SwiftUI

/// Keeps every evidence node whole and in source order, including historical text.
struct CaptureStagingMediaFlowLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let idealWidth = sizes.reduce(0) { $0 + $1.width } + CGFloat(max(0, sizes.count - 1)) * 8
        let offeredWidth = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? idealWidth
        let width = max(sizes.map(\.width).max() ?? 0, offeredWidth)
        let frames = Self.frames(sizes: sizes, width: width)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let frames = Self.frames(sizes: sizes, width: bounds.width)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading, proposal: ProposedViewSize(frame.size)
            )
        }
    }

    static func frames(sizes: [CGSize], width: CGFloat) -> [CGRect] {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        return sizes.map { size in
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + 8
                rowHeight = 0
            }
            let frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
            x += size.width + 8
            rowHeight = max(rowHeight, size.height)
            return frame
        }
    }
}
