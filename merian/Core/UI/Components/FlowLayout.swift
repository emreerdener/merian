import SwiftUI

public struct FlowLayout: Layout {
    public var spacing: CGFloat
    
    public init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }
    
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
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
        
        init(in maxWidth: CGFloat?, subviews: Subviews, spacing: CGFloat) {
            let limit = maxWidth ?? .infinity
            var currentPosition = CGPoint.zero
            var lineHeight: CGFloat = 0
            var frames: [CGRect] = []
            var maxX: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentPosition.x + size.width > limit, currentPosition.x > 0 {
                    currentPosition.x = 0
                    currentPosition.y += lineHeight + spacing
                    lineHeight = 0
                }
                
                frames.append(CGRect(origin: currentPosition, size: size))
                lineHeight = max(lineHeight, size.height)
                currentPosition.x += size.width + spacing
                maxX = max(maxX, currentPosition.x - spacing)
            }
            
            self.frames = frames
            self.size = CGSize(
                width: maxWidth == nil ? maxX : (limit == .infinity ? maxX : limit),
                height: currentPosition.y + lineHeight
            )
        }
    }
}
