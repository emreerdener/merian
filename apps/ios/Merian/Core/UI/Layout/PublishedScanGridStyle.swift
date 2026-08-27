import SwiftUI

enum PublishedScanGridStyle {
    static let columnCount = 3
    static let spacing: CGFloat = 2
    static let cornerRadius: CGFloat = 16

    static var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount)
    }

    static func cornerRadii(
        index: Int,
        itemCount: Int,
        columnCount: Int = PublishedScanGridStyle.columnCount
    ) -> RectangleCornerRadii {
        guard itemCount > 0 else { return RectangleCornerRadii() }

        let normalizedColumnCount = max(columnCount, 1)
        let row = index / normalizedColumnCount
        let column = index % normalizedColumnCount
        let totalRows = (itemCount + normalizedColumnCount - 1) / normalizedColumnCount

        func itemsInRow(_ row: Int) -> Int {
            min(normalizedColumnCount, itemCount - row * normalizedColumnCount)
        }

        let isTopLeft = row == 0 && column == 0
        let isTopRight = row == 0 && column == itemsInRow(0) - 1
        let isBottomLeft = column == 0 && row == totalRows - 1
        let hasNoCellBelow = row + 1 == totalRows || column >= itemsInRow(row + 1)
        let isBottomRight = column == itemsInRow(row) - 1 && hasNoCellBelow

        return RectangleCornerRadii(
            topLeading: isTopLeft ? cornerRadius : 0,
            bottomLeading: isBottomLeft ? cornerRadius : 0,
            bottomTrailing: isBottomRight ? cornerRadius : 0,
            topTrailing: isTopRight ? cornerRadius : 0
        )
    }
}

extension View {
    func publishedScanTileCorners(
        index: Int,
        itemCount: Int,
        columnCount: Int = PublishedScanGridStyle.columnCount
    ) -> some View {
        clipShape(
            UnevenRoundedRectangle(
                cornerRadii: PublishedScanGridStyle.cornerRadii(
                    index: index,
                    itemCount: itemCount,
                    columnCount: columnCount
                ),
                style: .continuous
            )
        )
    }
}
