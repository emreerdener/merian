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
    
    private var isMonthScale: Bool { scale == .month }
    
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
                    Image(systemName: "camera.viewfinder")
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
                if scale == .year {
                    FadingScrollView {
                        gridContent
                    }
                } else {
                    gridContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
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
    private var gridContent: some View {
        if heatmapData != nil {
            HeatmapGridMatrix(
                visibleWeeks: visibleWeeks,
                squareHeight: squareHeight,
                squareSpacing: squareSpacing,
                yAxisGap: yAxisGap,
                colorScheme: colorScheme,
                isMonthScale: isMonthScale
            )
            // Equatable conformation is extremely critical here, as it inherently stops thousands 
            // of Heatmap Rectangles from redundantly redrawing structurally unless root data mutates!
            .equatable()
            .padding(.horizontal, 16)
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

// MARK: - Isolated Grid Matrix
struct HeatmapGridMatrix: View, Equatable {
    let visibleWeeks: [HeatmapWeek]
    let squareHeight: CGFloat
    let squareSpacing: CGFloat
    let yAxisGap: CGFloat
    let colorScheme: ColorScheme
    let isMonthScale: Bool
    
    private func shouldDropLabel(at index: Int) -> Bool {
        if isMonthScale { return false }
        for jump in 1...3 {
            if index + jump < visibleWeeks.count, visibleWeeks[index + jump].monthLabel != nil {
                return true
            }
        }
        return false
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: squareSpacing) {
            // X-Axis Labels (Months)
            HStack(spacing: squareSpacing) {
                ForEach(Array(visibleWeeks.enumerated()), id: \.element.id) { index, week in
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
                    .frame(maxWidth: isMonthScale ? .infinity : nil, alignment: .leading)
                    .frame(width: isMonthScale ? nil : 11, alignment: .leading)
                }
                
                // Offset for Y-Axis labels
                Spacer().frame(width: 28 + yAxisGap)
            }
            
            Group {
                if isMonthScale {
                    HStack(alignment: .top, spacing: squareSpacing) {
                        gridBody
                    }
                } else {
                    LazyHStack(alignment: .top, spacing: squareSpacing) {
                        gridBody
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var gridBody: some View {
        // Weeks
        ForEach(visibleWeeks) { week in
            VStack(spacing: squareSpacing) {
                ForEach(week.days) { day in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(HeatmapColor.color(for: day.count, scheme: colorScheme))
                        .frame(maxWidth: isMonthScale ? .infinity : nil)
                        .frame(width: isMonthScale ? nil : 11, height: squareHeight)
                }
            }
            .frame(maxWidth: isMonthScale ? .infinity : nil)
        }
        
        // Y-Axis Labels (Moved to trailing edge)
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
    
    static func == (lhs: HeatmapGridMatrix, rhs: HeatmapGridMatrix) -> Bool {
        lhs.isMonthScale == rhs.isMonthScale &&
        lhs.colorScheme == rhs.colorScheme &&
        lhs.visibleWeeks.count == rhs.visibleWeeks.count &&
        zip(lhs.visibleWeeks, rhs.visibleWeeks).allSatisfy { $0.0.id == $0.1.id }
    }
}

// MARK: - Dynamic Fading ScrollView
struct FadingScrollView<Content: View>: View {
    @ViewBuilder let content: Content
    
    @State private var offset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content
                .background(
                    // Explicitly uses GeometryReader on a strict invisible Color.clear layer to globally 
                    // intercept CoordinateSpace offset tracking perfectly without hardcoding pixel widths!
                    GeometryReader { geo in
                        Color.clear
                            .onChange(of: geo.frame(in: .named("FadingScrollSpace")).minX, initial: true) { _, newX in
                                if abs(offset - newX) > 1.0 {
                                    Task { @MainActor in offset = newX }
                                }
                            }
                            .onChange(of: geo.size.width, initial: true) { _, newW in
                                if abs(contentWidth - newW) > 1.0 {
                                    Task { @MainActor in contentWidth = newW }
                                }
                            }
                    }
                )
        }
        .coordinateSpace(name: "FadingScrollSpace")
        .defaultScrollAnchor(.trailing)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.size.width, initial: true) { _, newW in
                        if abs(containerWidth - newW) > 1.0 {
                            Task { @MainActor in containerWidth = newW }
                        }
                    }
            }
        )
        .mask(
            HStack(spacing: 0) {
                let showLeadingFade = offset < -10
                LinearGradient(
                    gradient: Gradient(colors: [Color.black.opacity(showLeadingFade ? 0 : 1), .black]),
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 48)
                
                Rectangle().fill(Color.black)
                
                let maxScroll = max(0, contentWidth - containerWidth)
                let showTrailingFade = offset > -maxScroll + 10
                
                LinearGradient(
                    gradient: Gradient(colors: [.black, Color.black.opacity(showTrailingFade ? 0 : 1)]),
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 48)
            }
        )
    }
}
