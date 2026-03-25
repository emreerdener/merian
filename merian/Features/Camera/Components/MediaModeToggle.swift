import SwiftUI

/// Staging definition for the impending audio sensory boundary.
enum CaptureMode: String, CaseIterable {
    case visual
    case audio
}

/// A highly modular, glassmorphic capsule toggle controlling the active environmental capture state natively!
struct MediaModeToggle: View {
    @Binding var activeMode: CaptureMode
    let onModeChange: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var toggleSize: CGSize = .zero

    private var segmentWidth: CGFloat { toggleSize.width / 2 }

    private var pillX: CGFloat {
        if activeMode == .visual {
            return max(0, min(dragOffset, segmentWidth))
        } else {
            return segmentWidth + max(-segmentWidth, min(dragOffset, 0))
        }
    }

    private func labelColor(for mode: CaptureMode) -> Color {
        guard segmentWidth > 0 else {
            return activeMode == mode ? .black : .white.opacity(0.85)
        }
        let fraction = pillX / segmentWidth
        let isActive = mode == .visual ? fraction < 0.5 : fraction >= 0.5
        return isActive ? .black : .white.opacity(0.85)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CaptureMode.allCases, id: \.self) { mode in
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        activeMode = mode
                    }
                    onModeChange()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: mode == .visual ? "viewfinder" : "waveform")
                        Text(mode == .visual ? "Scan" : "Record")
                    }
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(labelColor(for: mode))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        // Size probe
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { toggleSize = geo.size }
                    .onChange(of: geo.size) { _, size in toggleSize = size }
            }
        }
        // White pill lives BEHIND the buttons so text renders on top and stays readable.
        .background(alignment: .leading) {
            if toggleSize != .zero {
                Capsule()
                    .fill(Color.white)
                    .frame(width: segmentWidth, height: toggleSize.height)
                    .offset(x: pillX)
            }
        }
        // Drag gesture on the container — only activates when starting on the active segment.
        .simultaneousGesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .local)
                .onChanged { value in
                    let startInActive = activeMode == .visual
                        ? value.startLocation.x < segmentWidth
                        : value.startLocation.x >= segmentWidth
                    guard startInActive else { return }
                    if activeMode == .visual {
                        dragOffset = max(0, min(value.translation.width, segmentWidth))
                    } else {
                        dragOffset = max(-segmentWidth, min(value.translation.width, 0))
                    }
                }
                .onEnded { value in
                    let startInActive = activeMode == .visual
                        ? value.startLocation.x < segmentWidth
                        : value.startLocation.x >= segmentWidth
                    if startInActive {
                        let threshold = segmentWidth / 2
                        if activeMode == .visual && dragOffset > threshold {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { activeMode = .audio }
                            onModeChange()
                        } else if activeMode == .audio && dragOffset < -threshold {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { activeMode = .visual }
                            onModeChange()
                        }
                    }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { dragOffset = 0 }
                }
        )
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.4), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
    }
}
