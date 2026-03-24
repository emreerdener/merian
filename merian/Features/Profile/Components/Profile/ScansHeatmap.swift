import SwiftUI

/// Abstracted computational Heatmap strictly decoupled to manage thousands of explicit Grid rectangles securely.
struct ScansHeatmap: View {
    @Environment(\.colorScheme) var colorScheme
    let heatmapData: ProfileHeatmapData?
    
    enum HeatmapScale: String, CaseIterable, Identifiable {
        case year = "year"
        case month = "month"
        var id: String { self.rawValue }
    }
    
    // Globally persists the user's explicit Zoom-level structurally mapping local defaults.
    @AppStorage("heatmapScaleSelection") private var scale: HeatmapScale = .month
    
    private let squareHeight: CGFloat = 11
    private let squareSpacing: CGFloat = 3
    private let yAxisGap: CGFloat = 6
    
    private var formattedTotalScans: String {
        guard let data = heatmapData else { return "0" }
        let count = scale == .month ? data.currentMonthCaptures : data.totalCaptures
        return count.formatted(.number)
    }
    
    private var visibleWeeks: [HeatmapWeek] {
        guard let data = heatmapData else { return [] }
        switch scale {
        case .year:
            return data.weeks
        case .month:
            return Array(data.weeks.suffix(5))
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Top Header Outside the Container
            if heatmapData != nil {
                HStack(spacing: 6) {
                    Image(systemName: "viewfinder")
                        .foregroundColor(.primary)
                    Text("\(formattedTotalScans) scans this")
                        .foregroundColor(.primary)
                    
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scale = scale == .year ? .month : .year
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(scale.rawValue)
                                .foregroundColor(.primary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 16)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading scans...")
                        .foregroundColor(.secondary)
                }
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 16)
            }
            
            // Grid Container (Canvas Base)
            VStack(alignment: .leading, spacing: 12) {
                groupGridContent
                
                // Bottom Row (Links + Legend)
                if heatmapData != nil {
                    HStack {
                        Spacer()
                        Text("Less")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        HStack(spacing: squareSpacing) {
                            
                            ForEach([0, 1, 3, 5, 7], id: \.self) { count in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(color(for: count))
                                    .frame(width: squareHeight, height: squareHeight)
                            }
                           
                        }
                        Text("More")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private var groupGridContent: some View {
        if heatmapData != nil {
            if scale == .year {
                FadingScrollView {
                    HeatmapYearGrid(
                        weeks: visibleWeeks,
                        colorFor: { count in color(for: count) }
                    )
                    // Equatable conformation is extremely critical here, as it inherently stops thousands 
                    // of Heatmap Rectangles from redundantly redrawing structurally unless root data mutates!
                    .equatable()
                    .padding(.horizontal, 16)
                }
            } else {
                HeatmapMonthGrid(
                    weeks: visibleWeeks,
                    colorFor: { count in color(for: count) }
                )
                .equatable()
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            // Skeleton/Loader
            HStack {
                Spacer()
                ProgressView()
                    .padding(.vertical, 32)
                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }
    
    private func color(for count: Int) -> Color {
        HeatmapColor.color(for: count, scheme: colorScheme)
    }
}

// MARK: - Color Helper
struct HeatmapColor {
    static func color(for count: Int, scheme: ColorScheme) -> Color {
        if count < 0 {
            return Color.clear // Future dates out of bounds
        } else if count == 0 {
            return scheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)
        } else if count == 1 {
            return Color.green.opacity(0.4)
        } else if count <= 3 {
            return Color.green.opacity(0.6)
        } else if count <= 5 {
            return Color.green.opacity(0.8)
        } else {
            return Color.green
        }
    }
}

// MARK: - Isolated Grid Views

private struct HeatmapMonthGrid: View, Equatable {
    let weeks: [HeatmapWeek]
    let colorFor: (Int) -> Color
    let squareHeight: CGFloat = 11
    let squareSpacing: CGFloat = 3
    let yAxisGap: CGFloat = 6
    
    var body: some View {
        VStack(alignment: .leading, spacing: squareSpacing) {
            // X-Axis Labels (Months)
            HStack(spacing: squareSpacing) {
                ForEach(Array(weeks.enumerated()), id: \.element.id) { index, week in
                    VStack(alignment: .leading) {
                        if let monthLabel = week.monthLabel {
                            Text(monthLabel)
                                .font(.caption2)
                                .foregroundColor(.primary)
                                .fixedSize()
                        } else {
                            Text("")
                                .font(.caption2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Offset for Y-Axis labels
                Spacer().frame(width: 28 + yAxisGap)
            }
            
            HStack(alignment: .top, spacing: squareSpacing) {
                ForEach(weeks) { week in
                    VStack(spacing: squareSpacing) {
                        ForEach(week.days) { day in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(colorFor(day.count))
                                .frame(maxWidth: .infinity)
                                .frame(height: squareHeight)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                
                // Y-Axis Labels
                VStack(alignment: .leading, spacing: squareSpacing) {
                    Color.clear.frame(height: squareHeight) // Sun
                    Text("Mon").font(.caption2).foregroundColor(.primary).frame(height: squareHeight)
                    Color.clear.frame(height: squareHeight) // Tue
                    Text("Wed").font(.caption2).foregroundColor(.primary).frame(height: squareHeight)
                    Color.clear.frame(height: squareHeight) // Thu
                    Text("Fri").font(.caption2).foregroundColor(.primary).frame(height: squareHeight)
                    Color.clear.frame(height: squareHeight) // Sat
                }
                .frame(width: 28, alignment: .leading)
                .padding(.leading, yAxisGap)
            }
        }
    }
    
    static func == (lhs: HeatmapMonthGrid, rhs: HeatmapMonthGrid) -> Bool {
        lhs.weeks.count == rhs.weeks.count &&
        zip(lhs.weeks, rhs.weeks).allSatisfy { $0.0.id == $0.1.id }
    }
}

private struct HeatmapYearGrid: View, Equatable {
    let weeks: [HeatmapWeek]
    let colorFor: (Int) -> Color
    let squareHeight: CGFloat = 11
    let squareSpacing: CGFloat = 3
    let yAxisGap: CGFloat = 6
    
    private func shouldDropLabel(at index: Int) -> Bool {
        for jump in 1...3 {
            if index + jump < weeks.count, weeks[index + jump].monthLabel != nil {
                return true
            }
        }
        return false
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: squareSpacing) {
            // X-Axis Labels (Months)
            HStack(spacing: squareSpacing) {
                ForEach(Array(weeks.enumerated()), id: \.element.id) { index, week in
                    VStack(alignment: .leading) {
                        if let monthLabel = week.monthLabel, !shouldDropLabel(at: index) {
                            Text(monthLabel)
                                .font(.caption2)
                                .foregroundColor(.primary)
                                .fixedSize()
                        } else {
                            Text("")
                                .font(.caption2)
                        }
                    }
                    .frame(width: 11, alignment: .leading)
                }
                
                // Offset for Y-Axis labels
                Spacer().frame(width: 28 + yAxisGap)
            }
            
            LazyHStack(alignment: .top, spacing: squareSpacing) {
                ForEach(weeks) { week in
                    VStack(spacing: squareSpacing) {
                        ForEach(week.days) { day in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(colorFor(day.count))
                                .frame(width: 11, height: squareHeight)
                        }
                    }
                }
                
                // Y-Axis Labels
                VStack(alignment: .leading, spacing: squareSpacing) {
                    Color.clear.frame(height: squareHeight) // Sun
                    Text("Mon").font(.caption2).foregroundColor(.primary).frame(height: squareHeight)
                    Color.clear.frame(height: squareHeight) // Tue
                    Text("Wed").font(.caption2).foregroundColor(.primary).frame(height: squareHeight)
                    Color.clear.frame(height: squareHeight) // Thu
                    Text("Fri").font(.caption2).foregroundColor(.primary).frame(height: squareHeight)
                    Color.clear.frame(height: squareHeight) // Sat
                }
                .frame(width: 28, alignment: .leading)
                .padding(.leading, yAxisGap)
            }
        }
    }
    
    static func == (lhs: HeatmapYearGrid, rhs: HeatmapYearGrid) -> Bool {
        lhs.weeks.count == rhs.weeks.count &&
        zip(lhs.weeks, rhs.weeks).allSatisfy { $0.0.id == $0.1.id }
    }
}
