import SwiftUI

struct ProfileCaptureHeatmapView: View {
    @Environment(\.colorScheme) var colorScheme
    let heatmapData: ProfileHeatmapData?
    
    private let squareSize: CGFloat = 11
    private let squareSpacing: CGFloat = 3
    private let yAxisGap: CGFloat = 6
    
    private var formattedTotalScans: String {
        guard let data = heatmapData else { return "0" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: data.totalCaptures)) ?? "\(data.totalCaptures)"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Top Header Outside the Container
            if heatmapData != nil {
                HStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                        .foregroundColor(.primary)
                    Text("\(formattedTotalScans) scans this year")
                        .foregroundColor(.primary)
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
                FadingScrollView {
                    if let data = heatmapData {
                        VStack(alignment: .leading, spacing: squareSpacing) {
                            // X-Axis Labels (Months)
                            HStack(spacing: squareSpacing) {
                                ForEach(data.weeks) { week in
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
                                    .frame(width: squareSize, alignment: .leading)
                                }
                                
                                // Offset for Y-Axis labels
                                Spacer().frame(width: 28 + yAxisGap)
                            }
                            
                            HStack(alignment: .top, spacing: squareSpacing) {
                                // Weeks
                                ForEach(data.weeks) { week in
                                    VStack(spacing: squareSpacing) {
                                        ForEach(week.days) { day in
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(color(for: day.count))
                                                .frame(width: squareSize, height: squareSize)
                                        }
                                    }
                                }
                                
                                // Y-Axis Labels (Moved to trailing edge)
                                VStack(alignment: .leading, spacing: squareSpacing) {
                                    Color.clear.frame(height: squareSize) // Sun
                                    Text("Mon").font(.caption2).foregroundColor(.primary).frame(height: squareSize)
                                    Color.clear.frame(height: squareSize) // Tue
                                    Text("Wed").font(.caption2).foregroundColor(.primary).frame(height: squareSize)
                                    Color.clear.frame(height: squareSize) // Thu
                                    Text("Fri").font(.caption2).foregroundColor(.primary).frame(height: squareSize)
                                    Color.clear.frame(height: squareSize) // Sat
                                }
                                .frame(width: 28, alignment: .leading)
                                .padding(.leading, yAxisGap)
                            }
                        }
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
                                    .frame(width: squareSize, height: squareSize)
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
    
    private func color(for count: Int) -> Color {
        if count < 0 {
            return Color.clear // Future dates out of bounds
        } else if count == 0 {
            return colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)
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
                    GeometryReader { geo in
                        Color.clear
                            .onChange(of: geo.frame(in: .named("FadingScrollSpace")).minX, initial: true) { _, newX in
                                offset = newX
                            }
                            .onChange(of: geo.size.width, initial: true) { _, newW in
                                contentWidth = newW
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
                        containerWidth = newW
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
