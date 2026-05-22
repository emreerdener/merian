import SwiftUI

public struct FlowLayout: Layout {
    public enum LineAlignment {
        case leading
        case center
    }

    public var spacing: CGFloat
    public var lineAlignment: LineAlignment
    
    public init(spacing: CGFloat = 8, lineAlignment: LineAlignment = .leading) {
        self.spacing = spacing
        self.lineAlignment = lineAlignment
    }
    
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.width,
            subviews: subviews,
            spacing: spacing,
            lineAlignment: lineAlignment
        )
        return result.size
    }
    
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing,
            lineAlignment: lineAlignment
        )
        for (index, subview) in subviews.enumerated() {
            let point = result.frames[index].origin
            subview.place(
                at: CGPoint(x: point.x + bounds.minX, y: point.y + bounds.minY),
                proposal: ProposedViewSize(result.frames[index].size)
            )
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []
        
        init(in maxWidth: CGFloat?, subviews: Subviews, spacing: CGFloat, lineAlignment: LineAlignment) {
            let limit = maxWidth ?? .infinity
            var currentPosition = CGPoint.zero
            var lineHeight: CGFloat = 0
            var frames: [CGRect] = []
            var maxX: CGFloat = 0
            var lineStartIndex = 0
            var lineRanges: [Range<Int>] = []
            var lineWidths: [CGFloat] = []
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentPosition.x + size.width > limit, currentPosition.x > 0 {
                    lineRanges.append(lineStartIndex..<frames.count)
                    lineWidths.append(max(0, currentPosition.x - spacing))
                    lineStartIndex = frames.count
                    currentPosition.x = 0
                    currentPosition.y += lineHeight + spacing
                    lineHeight = 0
                }
                
                frames.append(CGRect(origin: currentPosition, size: size))
                lineHeight = max(lineHeight, size.height)
                currentPosition.x += size.width + spacing
                maxX = max(maxX, currentPosition.x - spacing)
            }

            if lineStartIndex < frames.count {
                lineRanges.append(lineStartIndex..<frames.count)
                lineWidths.append(max(0, currentPosition.x - spacing))
            }

            let width = maxWidth == nil ? maxX : (limit == .infinity ? maxX : limit)
            if lineAlignment == .center {
                for (lineRange, lineWidth) in zip(lineRanges, lineWidths) {
                    let lineOffset = max(0, (width - lineWidth) / 2)
                    for index in lineRange {
                        frames[index].origin.x += lineOffset
                    }
                }
            }
            
            self.frames = frames
            self.size = CGSize(
                width: width,
                height: currentPosition.y + lineHeight
            )
        }
    }
}
