import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(for: subviews, availableWidth: proposal.width ?? 0)
        let height = rows.reduce(0.0) { $0 + $1.maxHeight } + max(0, CGFloat(rows.count - 1)) * spacing
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(for: subviews, availableWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                let size = item.sizeThatFits(.unspecified)
                item.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.maxHeight + spacing
        }
    }

    private struct Row {
        var items: [LayoutSubview] = []
        var maxHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
    }

    private func computeRows(for subviews: Subviews, availableWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let widthNeeded = current.items.isEmpty ? size.width : size.width + spacing
            if !current.items.isEmpty && current.totalWidth + widthNeeded > availableWidth {
                rows.append(current)
                current = Row()
            }
            current.items.append(subview)
            current.totalWidth += widthNeeded
            current.maxHeight = max(current.maxHeight, size.height)
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
