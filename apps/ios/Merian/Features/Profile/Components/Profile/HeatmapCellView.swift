import SwiftUI

// MARK: - Discrete Grid Cell Node
struct HeatmapCellView: View {
    let count: Int
    let scheme: ColorScheme
    let isMonthScale: Bool
    let squareHeight: CGFloat
    
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(HeatmapColor.color(for: count, scheme: scheme))
            .frame(maxWidth: isMonthScale ? .infinity : nil)
            .frame(width: isMonthScale ? nil : 11, height: squareHeight)
    }
}

// MARK: - Column Orchestration
struct HeatmapWeekColumnView: View {
    let week: HeatmapWeek
    let scheme: ColorScheme
    let isMonthScale: Bool
    let squareHeight: CGFloat
    let squareSpacing: CGFloat
    
    var body: some View {
        VStack(spacing: squareSpacing) {
            ForEach(week.days) { day in
                HeatmapCellView(
                    count: day.count,
                    scheme: scheme,
                    isMonthScale: isMonthScale,
                    squareHeight: squareHeight
                )
            }
        }
        .frame(maxWidth: isMonthScale ? .infinity : nil)
    }
}
