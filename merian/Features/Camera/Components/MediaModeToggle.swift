import SwiftUI

/// Staging definition for the impending audio sensory boundary.
enum CaptureMode: String, CaseIterable {
    case visual
    case audio
}

/// A highly modular, glassmorphic capsule toggle controlling the active environmental capture state natively!
struct MediaModeToggle: View {
    @Binding var activeMode: CaptureMode
    
    // Apple-tier smooth sliding pill animation explicitly bound geometrically
    @Namespace private var toggleAnimation
    
    // MARK: - Staging States
    @State private var showComingSoon = false
    @State private var tooltipTask: Task<Void, Never>?
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(CaptureMode.allCases, id: \.self) { mode in
                Button(action: {
                    if mode == .audio {
                        // Throw the "Coming soon" toast for Audio staging!
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            showComingSoon = true
                        }
                        
                        tooltipTask?.cancel()
                        tooltipTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            if !Task.isCancelled {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    showComingSoon = false
                                }
                            }
                        }
                    } else {
                        // Triggers the Apple-tier spring slide natively for Visual
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            activeMode = mode
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: mode == .visual ? "camera.viewfinder" : "waveform")
                        Text(mode == .visual ? "Visual" : "Audio")
                    }
                    .font(.subheadline)
                    .fontWeight(.bold)
                    // Dynamic contrast for readability!
                    .foregroundColor(activeMode == mode ? .black : .white.opacity(0.85))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle()) // Huge hit-box
                    // The sliding visual indicator natively anchors behind the active payload cleanly!
                    .background {
                        if activeMode == mode {
                            Capsule()
                                .fill(Color.white)
                                .matchedGeometryEffect(id: "ActiveModeIndicator", in: toggleAnimation)
                        }
                    }
                    .overlay(
                        Group {
                            if mode == .audio && showComingSoon {
                                Text("Coming soon")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(Color.blue)
                                    )
                                    // Pushes the toolip seamlessly DOWN explicitly avoiding the iOS notch boundaries
                                    .offset(y: 45)
                                    .transition(.scale(scale: 0.5, anchor: .top).combined(with: .opacity))
                                    .zIndex(100)
                            }
                        }
                        .allowsHitTesting(false)
                    )
                }
                .buttonStyle(PlainButtonStyle()) // Blocks default SwiftUI native blue highlighting
            }
        }
        .padding(4) // Snug bounding container explicitly enclosing the slide path!
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark) // Forces the material to physically render dark glassmorphism
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
